import { registry } from "@web/core/registry";
import { Base } from "@point_of_sale/app/models/related_models";
export class Category extends Base {
    static pythonModel = "pos.category";

    get states() {
        return this.models["pos.prep.state"].filter((state) =>
            state.categories.some((categ) => categ.id === this.id)
        );
    }
}

registry.category("pos_available_models").add(Category.pythonModel, Category);
