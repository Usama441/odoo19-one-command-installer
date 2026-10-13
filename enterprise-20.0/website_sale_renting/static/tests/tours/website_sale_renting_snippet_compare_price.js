import { registry } from "@web/core/registry";

registry.category("web_tour.tours").add("website_sale_renting_snippet_compare_price", {
    steps: () => [
        {
            content: "Check the compare price is shown on the sale product card",
            trigger: ".o_wsale_alternative_products .o_carousel_product_card[aria-label='Sale Product'] del:contains(150.00)",
        },
        {
            content: "Check the compare price is not shown on the rental product card",
            trigger: ".o_wsale_alternative_products .o_carousel_product_card[aria-label='Rental Product']:not(:has(del))",
        },
    ],
});
