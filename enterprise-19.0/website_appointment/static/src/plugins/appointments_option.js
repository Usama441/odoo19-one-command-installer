import { BaseOptionComponent } from "@html_builder/core/utils";
import { DynamicSnippetOption } from "@website/builder/plugins/options/dynamic_snippet_option";
import { useDynamicSnippetOption } from "@website/builder/plugins/options/dynamic_snippet_hook";

export class AppointmentsOption extends BaseOptionComponent {
    static template = "website_appointment.AppointmentsOption";
    static props = {
        ...DynamicSnippetOption.props,
    };
    setup() {
        super.setup();
        this.dynamicOptionParams = useDynamicSnippetOption(this.props.modelNameFilter);
    }
}
