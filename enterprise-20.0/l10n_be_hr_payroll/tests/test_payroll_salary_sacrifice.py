# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo.tests import tagged

from .common import TestPayrollCommon


@tagged('post_install_l10n', 'post_install', '-at_install', 'cafeteria_plan')
class TestSalarySacrificePayroll(TestPayrollCommon):

    def setUp(self):
        super().setUp()

        self.cafeteria_plan_benefit = self.env.ref("l10n_be_hr_payroll.l10n_be_cafeteria_plan")
        self.cafeteria_plan_benefit.active = True  # enable by default

    def test_cafeteria_plan_salary_rules(self):
        """
        The cafeteria plan comes with its salary rules. This test checks that they are applied correctly.

        1. The wage is the wage after the salary sacrifice: the sacrifice only keeps track of the shadow wage (wage
           + sacrifice) and changes neither the BASIC nor the ONSS of a month.

        2. Net contribution is deduced from the NET basket.
        """

        # SETUP
        employee = self.employee_georges
        emp_version = employee.version_id
        payslip_without = self.create_and_validate_payslips(
            employees=[employee],
            year=2025,
            months=[1],
        )

        emp_version.write({
            'l10n_be_cafeteria_plan_salary_sacrifice': 300.,
            'l10n_be_cafeteria_plan_net_contribution': 200.,
        })

        payslip_with = self.create_and_validate_payslips(
            employees=[employee],
            year=2025,
            months=[2],
        )

        # 1. BASIC and ONSS are those of the wage
        for code in ('BASIC', 'ONSS'):
            self.assertAlmostEqual(
                payslip_with.line_ids.filtered(lambda line: line.code == code).total,
                payslip_without.line_ids.filtered(lambda line: line.code == code).total,
                places=2,
                msg=f"The salary sacrifice should not change {code}.",
            )

        # 2. Net contribution line exists and appears on payslip
        line_net_contrib = payslip_with.line_ids.filtered(lambda line: line.code == 'NET.CONTRIBUTION')
        self.assertTrue(line_net_contrib, "Net contribution line should exist.")
        self.assertTrue(line_net_contrib.appears_on_payslip, "Net contribution should appear on the payslip.")
        self.assertAlmostEqual(line_net_contrib.total, -200.0)

    def test_disabled_cafeteria_plan_salary_rules(self):
        """
        When the benefit Cafeteria Plan is disabled, the rules linked to it should be disabled as well.
        Even though net contribution and salary sacrifice values are superior to 0.
        """
        self.cafeteria_plan_benefit.active = False

        employee = self.employee_georges
        employee.version_id.write({
            'l10n_be_cafeteria_plan_salary_sacrifice': 300.0,
            'l10n_be_cafeteria_plan_net_contribution': 200.0,
        })

        payslip = self.create_and_validate_payslips(
            employees=[employee],
            year=2025,
            months=[1],
        )

        self.assertNotIn('NET.CONTRIBUTION', payslip.line_ids.mapped('code'))
