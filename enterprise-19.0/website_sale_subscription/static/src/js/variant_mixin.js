import VariantMixin from '@website_sale/js/variant_mixin';

/**
 * Update the renting text when the combination change.
 *
 * @param {Event} ev
 * @param {Element} parent
 * @param {object} combination
 */
VariantMixin._onChangeCombinationSubscription = function (ev, parent, combination) {
    if (!combination.is_subscription) {
        return;
    }
    const unit = parent.querySelector(".o_subscription_unit");
    const price = parent.querySelector(".o_subscription_price") || parent.querySelector(".product_price h5");
    const addToCartButton = document.querySelector('#add_to_cart');

    if (combination.allow_one_time_sale) {
        parent.querySelector('.product_price')?.classList?.remove('d-inline-block');
    }

    if (addToCartButton) {
        addToCartButton.dataset.subscriptionPlanId = combination.pricings.length > 0 ? combination.subscription_default_pricing_plan_id : '';
    }
    if (unit) {
        unit.textContent = combination.temporal_unit_display;
    }
    if (price) {
        price.textContent = combination.subscription_default_pricing_price;
    }
};

const oldGetOptionalCombinationInfoParam = VariantMixin._getOptionalCombinationInfoParam;
/**
 * Add the selected plan to the optional combination info parameters.
 *
 * @param {Element} product
 */
VariantMixin._getOptionalCombinationInfoParam = function (product) {
    const result = oldGetOptionalCombinationInfoParam.apply(this, arguments);
    Object.assign(result, {
        'plan_id': product?.querySelector('.product_price .plan_select')?.value
    });

    return result;
};
