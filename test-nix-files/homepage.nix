{ config, ... }: {
  opnix = {
    systemdWantedBy = [ "homepage-dashboard" ];
    serviceAccountTokenPath = "/etc/op_service_account_token";
    secrets = {
      homepage-config.source = ''
        HOMEPAGE_VAR_TEST_SECRET="{{ op://opnix testing/opnix test/password }}"
      '';
    };
  };
  services.homepage-dashboard = {
    enable = true;
    environmentFile = config.opnix.secrets.homepage-config.path;
    widgets = [{
      greeting = {
        text_size = "xl";
        text = "{{HOMEPAGE_VAR_TEST_SECRET}}";
      };
    }];
  };
}
