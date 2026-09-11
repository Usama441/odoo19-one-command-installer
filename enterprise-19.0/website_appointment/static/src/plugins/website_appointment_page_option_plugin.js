import { Plugin } from "@html_editor/plugin";
import { _t } from "@web/core/l10n/translation";
import { registry } from "@web/core/registry";

class WebsiteAppointmentPageOption extends Plugin {
  static id = "websiteAppointmentPageOption";
  resources = {
    builder_options: [
      {
        template: "website_appointment.WebsiteAppointmentPageOption",
        selector: "main:has(.o_appointment_index)",
        title: _t("Appointments Page"),
        editableOnly: false,
        groups: ["website.group_website_designer"],
      },
    ],
  };
}

registry
  .category("website-plugins")
  .add(WebsiteAppointmentPageOption.id, WebsiteAppointmentPageOption);
