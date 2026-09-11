import { preSuperSetup, useDocumentView } from "@documents/views/hooks";
import { DocumentsControllerMixin } from "@documents/views/documents_controller_mixin";
import { DocumentsSelectionBox } from "@documents/views/selection_box/documents_selection_box";
import { onWillRender, useEffect, useRef, useState } from "@odoo/owl";
import { useService } from "@web/core/utils/hooks";
import { KanbanController } from "@web/views/kanban/kanban_controller";
import { Dropdown } from "@web/core/dropdown/dropdown";

export class DocumentsKanbanController extends DocumentsControllerMixin(KanbanController) {
    static template = "documents.DocumentsKanbanView";
    static components = {
        ...KanbanController.components,
        Dropdown,
        SelectionBox: DocumentsSelectionBox,
    };
    setup() {
        preSuperSetup();
        super.setup(...arguments);
        this.documentService = useService("document.document");
        this.uploadFileInputRef = useRef("uploadFileInput");
        const properties = useDocumentView(this.documentsViewHelpers());
        Object.assign(this, properties);
        this.firstLoadSelectId = this.documentService.initData?.documentId;
        this.documentStates = useState({
            previewStore: {},
        });
        this.rightPanelState = useState(this.documentService.rightPanelReactive);

        useEffect(
            () => {
                this.documentService.getSelectionActions = () => ({
                    getTopbarActions: () => this.getTopBarActionMenuItems(),
                    getMenuProps: () => this.actionMenuProps,
                });
            },
            () => []
        );

        /**
         * Open document preview when the view is loaded for a specific document such as in:
         *  * Direct access to the app via a document URL / _get_access_action
         *  * In-app redirection from shortcut
         */
        onWillRender(() => {
            if (!this.firstLoadSelectId) {
                return;
            }
            const initData = this.documentService.initData;
            const doc = this.model.root.records.find(
                (record) => record.data.id === this.firstLoadSelectId
            );
            if (doc) {
                this.firstLoadSelectId = false;
                doc.selected = true;
                if (initData.openPreview) {
                    initData.openPreview = false;
                    doc.onClickPreview(new Event("click"));
                }
            }
        });
    }

    get hasSelectedRecords() {
        return this.targetRecords.length;
    }

    get targetRecords() {
        return this.model.targetRecords;
    }

    /**
     * Override this to add view options.
     */
    documentsViewHelpers() {
        return {
            getSelectedDocumentsElements: () =>
                this.root?.el?.querySelectorAll(".o_kanban_record.o_record_selected") || [],
            setPreviewStore: (previewStore) => {
                this.documentStates.previewStore = previewStore;
            },
            isRecordPreviewable: this.isRecordPreviewable.bind(this),
        };
    }

    isRecordPreviewable(record) {
        return record.isViewable();
    }

    /**
     * Borrowed from ListController for ListView.Selection.
     */
    onUnselectAll() {
        this.model.root.selection.forEach((record) => {
            record.toggleSelection(false);
        });
        this.model.root.selectDomain(false);
    }

    /**
     * Select all the records for a selected domain
     */
    async onSelectDomain() {
        await this.model.root.selectDomain(true);
    }
}
