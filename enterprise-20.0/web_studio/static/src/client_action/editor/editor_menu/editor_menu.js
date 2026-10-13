import { _t } from "@web/core/l10n/translation";
import { localization } from "@web/core/l10n/localization";
import { registry } from "@web/core/registry";

import { Component, computed, onWillStart, onWillUpdateProps, proxy, t, useProps } from "@odoo/owl";
import { useStudioServiceAsReactive } from "@web_studio/studio_service";
import { useService } from "@web/core/utils/hooks";
import { useEnv } from "@web/owl2/utils";
const editorTabRegistry = registry.category("web_studio.editor_tabs");

class Breadcrumbs extends Component {
    static template = "web_studio.EditorMenu.Breadcrumbs";
    props = useProps({
        currentTab: t.object(),
        switchTab: t.function(),
    });
    editionFlow = useEnv().editionFlow;
    nextCrumbId = 0;

    baseCrumb = computed(() => {
        const currentTab = this.props.currentTab;
        return {
            id: `__base__${currentTab.id}`,
            data: {
                name: currentTab.name,
            },
            handler: () => this.props.switchTab({ tab: currentTab.id }),
        };
    });

    crumbs = computed(() => {
        const crumbs = [this.baseCrumb()];
        for (const c of this.env.editionFlow.breadcrumbs) {
            c.id ??= this.nextCrumbId++;
            crumbs.push(c);
        }
        return crumbs;
    });

    get breadcrumbs() {
        return this.crumbs();
    }
}

export class EditorMenu extends Component {
    static components = { Breadcrumbs };
    static template = "web_studio.EditorMenu";
    static viewTypes = [
        {
            title: _t("Form"),
            type: "form",
            icon: "contact_mail",
        },
        {
            title: _t("List"),
            type: "list",
            icon: "view_list",
        },
        {
            title: _t("Kanban"),
            type: "kanban",
            icon: "oi_view-kanban",
        },
        {
            title: _t("Map"),
            type: "map",
            icon: "location_on",
        },
        {
            title: _t("Calendar"),
            type: "calendar",
            icon: "calendar_today",
        },
        {
            title: _t("Graph"),
            type: "graph",
            icon: "area_chart",
        },
        {
            title: _t("Pivot"),
            type: "pivot",
            icon: "oi_view-pivot",
        },
        {
            title: _t("Gantt"),
            type: "gantt",
            icon: "view_timeline",
        },
        {
            title: _t("Cohort"),
            type: "cohort",
            icon: "oi_view-cohort",
        },
        {
            title: _t("Activity"),
            type: "activity",
            icon: "schedule",
        },
        {
            title: _t("Search"),
            type: "search",
            icon: "search",
        },
    ];

    props = useProps({
        switchTab: t.function(),
        switchView: t.function(),
    });

    setup() {
        this.l10n = localization;
        this.studio = useStudioServiceAsReactive();
        this.editionFlow = proxy(this.env.editionFlow);
    }

    get activeViews() {
        const action = this.studio.editedAction;
        const viewTypes = (action._views || action.views).map(([, type]) => type);
        return this.constructor.viewTypes.filter((vt) => viewTypes.includes(vt.type));
    }

    get editorTabs() {
        const entries = editorTabRegistry.getEntries();
        return entries.map((entry) => Object.assign({}, entry[1], { id: entry[0] }));
    }

    get currentTab() {
        return this.editorTabs.find((tab) => tab.id === this.studio.editorTab);
    }

    openTab(tab) {
        this.props.switchTab({ tab });
    }
}

editorTabRegistry
    .add("views", { name: _t("Views"), action: "web_studio.action_editor" }, { sequence: 10 })
    .add("automations", { name: _t("Automations") }, { sequence: 20 })
    .add("actions_server", { name: _t("Actions") }, { sequence: 30 })
    .add("automation_webhooks", { name: _t("Webhooks") }, { sequence: 40 })
    .add("access", { name: _t("Security") }, { sequence: 50 })
    .add("filters", { name: _t("Filter Rules") }, { sequence: 60 });

export class BaseEditorTabComponent extends Component {
    static template = "web_studio.EditorMenu.BaseEditorTabComponent";
    props = useProps({
        tab: t.object(),
        editedAction: t.object(),
        openTab: t.function(),
    });

    setup() {
        this.studio = useService("studio");
        onWillStart(() => this.updateFromModel(this.props.editedAction.res_model));
        onWillUpdateProps((next) => this.updateFromModel(next.editedAction.res_model));
    }

    onClick() {
        if (this.isDisabled) {
            return;
        }
        this.props.openTab(this.props.tab.id);
    }

    get isDisabled() {
        return false;
    }

    get tooltip() {
        return false;
    }

    async updateFromModel(resModel) {
        this.modelInfo = await this.studio.IrModelInfo.read(resModel);
    }
}
