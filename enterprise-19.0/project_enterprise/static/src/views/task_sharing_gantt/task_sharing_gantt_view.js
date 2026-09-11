import { registry } from "@web/core/registry";
import { ganttView } from "@web_gantt/gantt_view";

import { TaskGanttArchParserCommon } from "@project_enterprise/views/project_task_common/task_gantt_arch_parser_common";
import { TaskSharingGanttController } from "./task_sharing_gantt_controller";
import { TaskSharingGanttRenderer } from "./task_sharing_gantt_renderer";
import { TaskGanttModelCommon } from "@project_enterprise/views/project_task_common/task_gantt_model_common";


const viewRegistry = registry.category("views");

export const taskSharingGanttView = {
    ...ganttView,
    Controller: TaskSharingGanttController,
    ArchParser: TaskGanttArchParserCommon,
    Model: TaskGanttModelCommon,
    Renderer: TaskSharingGanttRenderer,
};

viewRegistry.add("task_sharing_gantt", taskSharingGanttView);
