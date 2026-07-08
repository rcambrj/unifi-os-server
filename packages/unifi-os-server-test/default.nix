{
  flake,
  pkgs,
}:

pkgs.testers.runNixOSTest {
  name = "unifi-os-server-test";

  nodes = {
    machine =
      { pkgs, ... }:
      let
        completeSetupWizard = pkgs.writers.writePython3Bin "complete-unifi-setup-wizard" {
          flakeIgnore = [
            "E302"
            "E501"
            "W503"
          ];
          libraries = [ pkgs.python3Packages.selenium ];
        } ''
          from selenium import webdriver
          from selenium.common.exceptions import TimeoutException
          from selenium.webdriver.chrome.options import Options
          from selenium.webdriver.chrome.service import Service
          from selenium.webdriver.common.by import By
          from selenium.webdriver.support.ui import WebDriverWait


          PASSWORD = "Nixos-test-1!"


          def page_text(driver):
              return driver.find_element(By.TAG_NAME, "body").text

          def click_text(driver, label, timeout=30):
              lower_label = label.lower()

              def find(_driver):
                  for element in _driver.find_elements(
                      By.CSS_SELECTOR,
                      "button, a, label, [role='button'], [role='checkbox']",
                  ):
                      if not element.is_displayed() or not element.is_enabled():
                          continue
                      texts = [
                          text.strip().lower()
                          for text in [
                              element.text,
                              element.get_attribute("aria-label"),
                              element.get_attribute("value"),
                          ]
                          if text
                      ]
                      if any(lower_label in text for text in texts):
                          return element
                  return False

              try:
                  element = WebDriverWait(driver, timeout).until(find)
              except TimeoutException as exception:
                  raise TimeoutException(
                      f"Timed out clicking {label!r} at {driver.current_url}\n{page_text(driver)}"
                  ) from exception
              element.click()

          def clipboard_text(driver):
              return driver.execute_async_script(
                  """
                  const done = arguments[0];
                  navigator.clipboard.readText().then(done, () => done(null));
                  """
              )


          def select_checkboxes_in_context(driver, context_text):
              return driver.execute_script(
                  """
                  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "checked").set;
                  const contextText = arguments[0].toLowerCase();
                  const context = [...document.querySelectorAll("*")]
                    .filter((element) => element.innerText && element.innerText.toLowerCase().includes(contextText))
                    .filter((element) => element.querySelector("input[type='checkbox']"))
                    .sort((a, b) => a.innerText.length - b.innerText.length)[0];

                  if (!context) {
                    return false;
                  }

                  const inputs = [...context.querySelectorAll("input[type='checkbox']")];
                  for (const input of inputs) {
                    if (!input.checked) {
                      setter.call(input, true);
                      input.dispatchEvent(new Event("input", { bubbles: true }));
                      input.dispatchEvent(new Event("change", { bubbles: true }));
                    }
                  }

                  return inputs.every((input) => input.checked);
                  """,
                  context_text,
              )


          options = Options()
          options.binary_location = "${pkgs.chromium}/bin/chromium"
          options.add_argument("--headless=new")
          options.add_argument("--no-sandbox")
          options.add_argument("--disable-dev-shm-usage")
          options.add_argument("--ignore-certificate-errors")
          options.add_argument("--window-size=1440,1200")

          driver = webdriver.Chrome(
              service=Service("${pkgs.chromedriver}/bin/chromedriver"),
              options=options,
          )

          try:
              driver.execute_cdp_cmd(
                  "Browser.grantPermissions",
                  {
                      "origin": "https://localhost:11443",
                      "permissions": ["clipboardReadWrite", "clipboardSanitizedWrite"],
                  },
              )
              driver.get("https://localhost:11443")

              name_input = WebDriverWait(driver, 300).until(
                  lambda d: d.find_element(By.CSS_SELECTOR, "input[name*='name' i]")
              )
              name_input.clear()
              name_input.send_keys("NixOS Test")
              click_text(driver, "next")

              # Stay local-only. Do not sign in with, create, or register a UI.com account.
              WebDriverWait(driver, 120).until(lambda d: "Create a UI Account" in page_text(d))
              click_text(driver, "proceed without a ui account")
              click_text(driver, "continue anyway")
              WebDriverWait(driver, 120).until(lambda d: "Set Console password" in page_text(d))

              password_inputs = WebDriverWait(driver, 30).until(
                  lambda d: [
                      element
                      for element in d.find_elements(By.CSS_SELECTOR, "input[type='password']")
                      if element.is_displayed() and element.is_enabled()
                  ] or False
              )
              for element in password_inputs:
                  element.clear()
                  element.send_keys(PASSWORD)

              WebDriverWait(driver, 30).until(
                  lambda d: select_checkboxes_in_context(d, "I understand and agree to Terms of Service and Privacy Policy")
              )
              click_text(driver, "finish")
              WebDriverWait(driver, 300).until(lambda d: "Setup Complete" in page_text(d))
              click_text(driver, "go to dashboard")

              WebDriverWait(driver, 300).until(lambda d: "Inform URL" in page_text(d))
              click_text(driver, "inform url")
              actual_inform_url = WebDriverWait(driver, 30).until(clipboard_text)
              assert actual_inform_url == "http://127.0.0.1:8080/inform", actual_inform_url
          finally:
              driver.quit()
        '';
      in
      {
        imports = [
          flake.nixosModules.unifi-os-server
        ];

        virtualisation = {
          diskSize = 16384;
          memorySize = 4096;
          podman.enable = true;
          oci-containers.backend = "podman";
        };

        environment.systemPackages = [
          completeSetupWizard
        ];

        networking.extraHosts = ''
          127.0.0.1 account.ui.com
          127.0.0.1 sso.ui.com
          127.0.0.1 unifi.ui.com
        '';

        services.unifi-os-server = {
          enable = true;
        };
      };
  };

  testScript = ''
    start_all()

    machine.wait_for_unit("podman-unifi-os-server.service")
    machine.wait_until_succeeds(
        "body=$(curl -ksf https://localhost:11443) && printf '%s' \"$body\" | grep -F 'window.UNIFI_OS_MANIFEST' >/dev/null && printf '%s' \"$body\" | grep -F 'UniFi OS Server' >/dev/null",
        timeout=120,
    )
    machine.succeed("complete-unifi-setup-wizard")
  '';
}
