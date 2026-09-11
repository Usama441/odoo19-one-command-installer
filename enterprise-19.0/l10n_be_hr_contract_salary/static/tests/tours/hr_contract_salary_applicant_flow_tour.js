import { registry } from "@web/core/registry";
import { patch } from "@web/core/utils/patch";
import "@hr_contract_salary/../tests/tours/hr_contract_salary_applicant_flow_tour";


patch(registry.category("web_tour.tours").get("hr_contract_salary_applicant_flow_tour"), {
    steps() {
        const originalSteps = super.steps();
        const nextStep = originalSteps.findIndex(
            (step) => step.id === "submit_step",
        );

        return [
            ...originalSteps.slice(0, nextStep),
            {
                content: "Language",
                trigger: "select[name=lang]:not(:visible)",
                run: "selectByLabel English",
            },
            ...originalSteps.slice(nextStep),
        ];
    }
});
