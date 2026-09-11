import { DYNAMIC_SNIPPET } from "@website/builder/plugins/options/dynamic_snippet_option_plugin";
import { Plugin } from "@html_editor/plugin";
import { withSequence } from "@html_editor/utils/resource";
import { registry } from "@web/core/registry";
import { AppointmentsOption } from "./appointments_option";

class AppointmentsOptionPlugin extends Plugin {
    static id = "AppointmentsOption";
    static dependencies = ["dynamicSnippetOption"];
    modelNameFilter = "appointment.type";
    selector = ".s_appointments";
    resources = {
        builder_options: withSequence(DYNAMIC_SNIPPET, {
            OptionComponent: AppointmentsOption,
            props: {
                modelNameFilter: this.modelNameFilter,
            },
            selector: this.selector,
        }),
        on_snippet_dropped_handlers: this.onSnippetDropped.bind(this),
    };
    async onSnippetDropped({ snippetEl }) {
        if (snippetEl.matches(this.selector)) {
            await this.dependencies.dynamicSnippetOption.setOptionsDefaultValues(
                snippetEl,
                this.modelNameFilter
            );
        }
    }
}

registry
    .category("website-plugins")
    .add(AppointmentsOptionPlugin.id, AppointmentsOptionPlugin);
