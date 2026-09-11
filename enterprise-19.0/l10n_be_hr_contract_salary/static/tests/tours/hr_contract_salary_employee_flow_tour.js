import { registry } from "@web/core/registry";
import { patch } from "@web/core/utils/patch";
import { inputFiles } from "@web/../tests/utils";
import "@hr_contract_salary/../tests/tours/hr_contract_salary_employee_flow_tour";


patch(registry.category("web_tour.tours").get("hr_contract_salary_employee_flow_tour"), {
    steps() {
        const originalSteps = super.steps();
        const nextStep = originalSteps.findIndex(
            (step) => step.id === "certificate_step",
        );
        return [
            ...originalSteps.slice(0, nextStep),
            {
                content: "Language",
                trigger: "select[name=lang]:not(:visible)",
                run: "selectByLabel English",
            },
            {
                content: "Upload ID card copy (Both Sides)",
                trigger: 'input[name="id_card"]',
                async run() {
                    const file = new File(["hello, world"], "employee_id_card.pdf", {
                        type: "application/pdf",
                    });
                    await inputFiles('input[name="id_card"]', [file]);
                },
            },
            {
                content: "Upload Mobile Subscription Invoice",
                trigger: 'input[name="mobile_invoice"]',
                async run() {
                    const file = new File(["hello, world"], "employee_mobile_invoice.pdf", {
                        type: "application/pdf",
                    });

                    await inputFiles('input[name="mobile_invoice"]', [file]);
                },
            },
            {
                content: "Upload Sim Card Copy",
                trigger: 'input[name="sim_card"]',
                async run() {
                    const file = new File(["hello, world"], "employee_sim_card.pdf", {
                        type: "application/pdf",
                    });

                    await inputFiles('input[name="sim_card"]', [file]);
                },
            },
            {
                content: "Upload Internet Subscription invoice",
                trigger: 'input[name="internet_invoice"]',
                async run() {
                    const file = new File(["hello, world"], "employee_internet_invoice.pdf", {
                        type: "application/pdf",
                    });
                    await inputFiles('input[name="internet_invoice"]', [file]);
                },
            },
            ...originalSteps.slice(nextStep)
        ]
    }
});
