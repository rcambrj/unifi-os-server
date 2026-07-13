{
  flake,
  pkgs,
}:

pkgs.testers.runNixOSTest {
  name = "unifi-os-server-test";

  nodes = {
    machine =
      { lib, pkgs, ... }:
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
          from selenium.common.exceptions import TimeoutException, WebDriverException
          from selenium.webdriver.chrome.options import Options
          from selenium.webdriver.chrome.service import Service
          from selenium.webdriver.common.by import By
          from selenium.webdriver.support.ui import WebDriverWait


          PASSWORD = "Nixos-test-1!"


          def page_text(driver):
              return driver.find_element(By.TAG_NAME, "body").text


          def page_html(driver):
              return driver.execute_script("return document.documentElement.outerHTML")


          def safe_page_html(driver):
              try:
                  return page_html(driver)
              except Exception as exception:
                  return f"<failed to read page HTML: {exception}>"


          def timeout_message(driver, description):
              return f"Timed out {description} at {driver.current_url}\n\nPage HTML:\n{safe_page_html(driver)}"


          def wait_until(driver, timeout, description, condition):
              def check(_driver):
                  try:
                      return condition(_driver)
                  except WebDriverException:
                      return False

              try:
                  return WebDriverWait(driver, timeout).until(check, timeout_message(driver, description))
              except TimeoutException as exception:
                  exception.msg = timeout_message(driver, description)
                  exception.screen = None
                  exception.stacktrace = None
                  raise

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
                  exception.msg = timeout_message(driver, f"clicking {label!r}")
                  exception.screen = None
                  exception.stacktrace = None
                  raise
              element.click()

          def clipboard_text(driver):
              return driver.execute_async_script(
                  """
                  const done = arguments[0];
                  navigator.clipboard.readText().then(done, () => done(null));
                  """
              )


          def select_terms_checkboxes(driver):
              return driver.execute_script(
                  """
                  const checkboxes = [...document.querySelectorAll("input[name='tosAndEula'][type='checkbox']")];
                  if (checkboxes.length === 0) {
                    return false;
                  }

                  for (const checkbox of checkboxes) {
                    if (!checkbox.checked) {
                      checkbox.click();
                    }
                  }

                  const finish = [...document.querySelectorAll("button")]
                    .find((button) => button.innerText.trim().toLowerCase() === "finish");

                  return checkboxes.every((checkbox) => checkbox.checked) && finish && !finish.disabled;
                  """
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

              name_input = wait_until(
                  driver,
                  300,
                  "waiting for console name input",
                  lambda d: d.find_element(By.CSS_SELECTOR, "input[name*='name' i]")
              )
              name_input.clear()
              name_input.send_keys("NixOS Test")
              click_text(driver, "next")

              # Stay local-only. Do not sign in with, create, or register a UI.com account.
              wait_until(
                  driver,
                  120,
                  "waiting for UI account choice",
                  lambda d: "Create a UI Account" in page_text(d),
              )
              click_text(driver, "proceed without a ui account")
              click_text(driver, "continue anyway")
              wait_until(
                  driver,
                  120,
                  "waiting for console password step",
                  lambda d: "Set Console password" in page_text(d),
              )

              password_inputs = wait_until(
                  driver,
                  30,
                  "waiting for password inputs",
                  lambda d: [
                      element
                      for element in d.find_elements(By.CSS_SELECTOR, "input[type='password']")
                      if element.is_displayed() and element.is_enabled()
                  ] or False
              )
              for element in password_inputs:
                  element.clear()
                  element.send_keys(PASSWORD)

              wait_until(
                  driver,
                  120,
                  "selecting Terms checkbox",
                  select_terms_checkboxes
              )
              click_text(driver, "finish")
              wait_until(
                  driver,
                  300,
                  "waiting for setup completion",
                  lambda d: "Setup Complete" in page_text(d),
              )
              click_text(driver, "go to dashboard")

              wait_until(
                  driver,
                  300,
                  "waiting for Inform URL",
                  lambda d: "Inform URL" in page_text(d),
              )
              click_text(driver, "inform url")
              actual_inform_url = wait_until(
                  driver,
                  30,
                  "waiting for clipboard Inform URL",
                  clipboard_text,
              )
              assert actual_inform_url == "http://192.0.2.10:8080/inform", actual_inform_url
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
          uosSystemIP = "192.0.2.10";
        };

        systemd.services.podman-unifi-os-server.preStart = lib.mkBefore ''
          system_properties="/var/lib/unifi-os-server/unifi/system.properties"
          if [ ! -e "$system_properties" ]; then
            printf '%s\n' \
              'unifi.https.hsts=true' \
              '# system_ip=a.b.c.d' \
              > "$system_properties"
          fi
        '';
      };
  };

  testScript = ''
    start_all()

    machine.wait_for_unit("podman-unifi-os-server.service")
    machine.succeed("grep -Fx 'system_ip=192.0.2.10' /var/lib/unifi-os-server/unifi/system.properties")
    machine.wait_until_succeeds(
        "body=$(curl -ksf https://localhost:11443) && printf '%s' \"$body\" | grep -F 'window.UNIFI_OS_MANIFEST' >/dev/null && printf '%s' \"$body\" | grep -F 'UniFi OS Server' >/dev/null",
        timeout=120,
    )
    machine.succeed("complete-unifi-setup-wizard")
  '';
}
