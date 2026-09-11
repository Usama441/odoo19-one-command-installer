import { BaseOptionComponent, useDomState } from "@html_builder/core/utils";
import { onWillStart } from "@odoo/owl";
import { Deferred } from "@web/core/utils/concurrency";

const { DateTime } = luxon;

export class OnlineAppointmentOption extends BaseOptionComponent {
    static template = "website_appointment.OnlineAppointmentOption";
    static components = { ...BaseOptionComponent };
    static props = {
        setDatasetProperty: Function,
        getDatasetProperty: Function,
        fetchAppointmentTypes: Function,
    };

    setup() {
        super.setup();
        this.datetime_now = DateTime.now().toFormat("yyyy-MM-dd HH:mm:ss");
        this.current_website = this.env.services.website.currentWebsite;
        const onReady = new Deferred();
        this.state = useDomState(
            async (editingElement) => {
                await onReady;
                const appointmentTypes = JSON.parse(editingElement.dataset.appointmentTypes);
                const currentAppointmentId =
                    appointmentTypes.length === 1 ? appointmentTypes[0] : null;
                let staffUserIds = [];
                if (currentAppointmentId !== null) {
                    staffUserIds = this.allAppointmentTypesById[
                        currentAppointmentId
                    ].staff_users.map((user) => user.id);
                }
                return {
                    currentAppointmentId: currentAppointmentId,
                    staffUserIds: staffUserIds,
                };
            },
        );
        onWillStart(async () => {
            await this.onWillStart();
            onReady.resolve();
        });
    }

    async onWillStart() {
        const el = this.env.getEditingElement();
        this.allAppointmentTypesById = await this.props.fetchAppointmentTypes();
        // If no appointments are available as opposed to when the button was created.
        if (!Object.keys(this.allAppointmentTypesById).length) {
            this.props.setDatasetProperty(el, "targetTypes", "all");
        } else if (this.props.getDatasetProperty(el, "targetTypes") !== "all") {
            // Handle case where (some) selected appointments are no longer available
            const selectedAppointmentTypesIds = this.props.getDatasetProperty(
                el,
                "appointmentTypes",
                true
            );
            const appointmentTypeIdsToKeep = selectedAppointmentTypesIds.filter((apptId) => {
                return Object.prototype.hasOwnProperty.call(this.allAppointmentTypesById, apptId);
            });
            if (!appointmentTypeIdsToKeep.length) {
                this.props.setDatasetProperty(el, "targetTypes", "all");
            } else if (appointmentTypeIdsToKeep.length !== selectedAppointmentTypesIds.length) {
                this.props.setDatasetProperty(el, "appointmentTypes", appointmentTypeIdsToKeep);
            } else {
                // Handle case where selected staffUsers(s) no longer available
                if (this.props.getDatasetProperty(el, "targetUsers") !== "all") {
                    const selectedUserIds = this.props.getDatasetProperty(el, "staffUsers", true);
                    const availableUserIds = this.allAppointmentTypesById[
                        selectedAppointmentTypesIds[0]
                    ].staff_users.map((u) => u.id);
                    const userIdsToKeep = selectedUserIds.filter((uid) =>
                        availableUserIds.includes(uid)
                    );
                    if (!userIdsToKeep.length) {
                        this.props.setDatasetProperty(el, "targetUsers", "all");
                    } else if (userIdsToKeep.length !== selectedUserIds.length) {
                        this.props.setDatasetProperty(el, "staffUsers", userIdsToKeep);
                    }
                }
            }
        }
    }
}
