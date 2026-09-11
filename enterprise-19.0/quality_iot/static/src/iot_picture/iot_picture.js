import { Component } from "@odoo/owl";
import { _t } from "@web/core/l10n/translation";
import { registry } from '@web/core/registry';
import { Dialog } from "@web/core/dialog/dialog";
import { useService } from '@web/core/utils/hooks';
import { ImageField, imageField } from '@web/views/fields/image/image_field';
import { useIotDevice } from '@iot/iot_device_hook';

class ImagePreviewDialog extends Component {
    static components = { Dialog };
    static template = "quality_iot.ImagePreviewDialog";
    static props = {
        src: String,
        close: Function,
    };
}

export class TabletImageIoTField extends ImageField {
    static template = "quality_iot.TabletImageIoTField";
    static props = {
        ...ImageField.props,
        ip_field: { type: String, optional: true },
        identifier_field: { type: String, optional: true },
    };

    setup() {
        super.setup();
        this.dialog = useService('dialog');
        this.notification = useService('notification');
        const iotIp = this.props.record.data[this.props.ip_field];
        const identifier = this.props.record.data[this.props.identifier_field];
        if (!iotIp || !identifier) {
            this.notification.add(
                _t('Please link the corresponding Quality Control Point to the camera.'), {
                title: _t('Camera configuration error'),
                type: 'warning',
            });
            return;
        }
        if (this.props.record.data.test_type !== 'picture') return;
        this.getIotDevice = useIotDevice({
            getIotIp: () => iotIp,
            getIdentifier: () => identifier,
            onValueChange: (data) => {
                if (data.owner && data.owner === data.session_id) {
                    if (data.image && data.message) {
                        this.notification.add(_t(data.message), { type: 'success' });
                        this.props.record.update({ [this.props.name]: data.image });
                    } else {
                        this.notifyFailure();
                    }
                }
            },
        });
    }
    async onTakePicture() {
        if (!this.getIotDevice) return;

        this.notification.add(_t('Capturing image...'), { type: 'info' });
        try {
            const data = await this.getIotDevice().action({});
            if (data.result !== true) {
                this.notifyFailure();
            }
            return data;
        } catch {
            this.notifyFailure();
        }
    }

    notifyFailure() {
        this.notification.add(_t('Please check if the device is still connected.'), {
            type: 'danger',
            title: _t('Connection to device failed'),
        });
    }

    openModal() {
        this.dialog.add(ImagePreviewDialog, {
            src: this.getUrl(this.props.name),
        });
    }
}

export const tabletImageIoTField = {
    ...imageField,
    component: TabletImageIoTField,
    extractProps({ options }) {
        const props = imageField.extractProps(...arguments);
        props.ip_field = options.ip_field;
        props.identifier_field = options.identifier;
        return props;
    },
};

registry.category("fields").add("iot_picture", tabletImageIoTField);
