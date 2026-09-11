# Part of Odoo. See LICENSE file for full copyright and licensing details.

from datetime import date

from odoo.fields import Command
from odoo.tests import tagged
from odoo.addons.hr_payroll_account.tests.common import TestPayslipValidationCommon


@tagged('post_install', 'post_install_l10n', '-at_install', 'payslips_validation')
class TestPayslipValidation(TestPayslipValidationCommon):

    @classmethod
    @TestPayslipValidationCommon.setup_country('ae')
    def setUpClass(cls):
        super().setUpClass()
        cls._setup_common(
            country=cls.env.ref('base.ae'),
            structure=cls.env.ref('l10n_ae_hr_payroll.uae_employee_payroll_structure'),
            structure_type=cls.env.ref('l10n_ae_hr_payroll.uae_employee_payroll_structure_type'),
            contract_fields={
                'wage': 40000.0,
                'l10n_ae_housing_allowance': 400.0,
                'l10n_ae_transportation_allowance': 220.0,
                'l10n_ae_other_allowances': 100.0,
                'l10n_ae_is_dews_applied': True,
            }
        )

        cls.work_entry_types = {
            entry_type.code: entry_type
            for entry_type in cls.env['hr.work.entry.type'].search([])
        }

    def _get_input_line_amount(self, payslip, code):
        input_lines = payslip.input_line_ids.filtered(lambda line: line.code == code)
        amounts = input_lines.mapped('amount')
        return len(amounts), sum(amounts)

    @classmethod
    def _create_worked_days(cls, name=False, code=False, number_of_days=0, number_of_hours=0):
        return Command.create({
            'name': name,
            'work_entry_type_id': cls.work_entry_types[code].id,
            'code': code,
            'number_of_days': number_of_days,
            'number_of_hours': number_of_hours,
        })

    def test_payslip_1(self):
        payslip = self._generate_payslip(date(2024, 1, 1), date(2024, 1, 31))
        payslip_results = {'BASIC': 40000.0, 'HOUALLOW': 400.0, 'TRAALLOW': 220.0, 'OTALLOW': 100.0, 'EOSP': 3333.33, 'ALP': 3393.33, 'GROSS': 40720.0, 'SICC': 5090.0, 'SIEC': -2036.0, 'DEWS': -3332.0, 'NET': 35352.0}
        self._validate_payslip(payslip, payslip_results)

    def test_payslip_2(self):
        payslip = self._generate_payslip(date(2024, 1, 1), date(2024, 1, 31))
        other_inputs_to_add = [
            (self.env.ref('l10n_ae_hr_payroll.input_salary_arrears'), 1000),
            (self.env.ref('l10n_ae_hr_payroll.input_other_earnings'), 2000),
            (self.env.ref('l10n_ae_hr_payroll.input_salary_deduction'), 500),
            (self.env.ref('l10n_ae_hr_payroll.input_other_deduction'), 200),
            (self.env.ref('l10n_ae_hr_payroll.l10n_ae_input_overtime_allowance'), 300),
            (self.env.ref('l10n_ae_hr_payroll.input_bonus_earnings'), 400),
            (self.env.ref('l10n_ae_hr_payroll.l10n_ae_input_other_allowance'), 600),
            (self.env.ref('l10n_ae_hr_payroll.input_airfare_allowance_earnings'), 700),
        ]
        for other_input, amount in other_inputs_to_add:
            self._add_other_input(payslip, other_input, amount)
        payslip.compute_sheet()

        payslip_results = {'BASIC': 40000.0, 'HOUALLOW': 400.0, 'TRAALLOW': 220.0, 'OTALLOW': 100.0, 'SALARY_ARREARS': 1000.0, 'OTHER_EARNINGS': 2000.0, 'SALARY_DEDUCTIONS': -500.0, 'OTHER_DEDUCTIONS': -200.0, 'OVERTIMEALLOWINP': 300.0, 'BONUS': 400.0, 'OTALLOWINP': 600.0, 'AIRFARE_ALLOWANCE': 700.0, 'EOSP': 3333.33, 'ALP': 3393.33, 'GROSS': 45720.0, 'SICC': 5090.0, 'SIEC': -2036.0, 'DEWS': -3332.0, 'NET': 39652.0}
        self._validate_payslip(payslip, payslip_results)

    def test_instant_pay_payslip_generation(self):
        instant_pay_structure = self.env.ref('l10n_ae_hr_payroll.l10n_ae_uae_instant_pay')
        payslip = self._generate_payslip(date(2023, 3, 1), date(2023, 3, 31), struct_id=instant_pay_structure.id)
        other_inputs_to_add = [
            (self.env.ref('l10n_ae_hr_payroll.l10n_ae_input_allowance'), 1000),
            (self.env.ref('l10n_ae_hr_payroll.l10n_ae_input_commission'), 800),
            (self.env.ref('l10n_ae_hr_payroll.l10n_ae_input_salary_advance'), 1500),
            (self.env.ref('l10n_ae_hr_payroll.l10n_ae_input_loan_advance'), 1200),
            (self.env.ref('l10n_ae_hr_payroll.l10n_ae_input_deduction'), 700),
        ]
        for other_input, amount in other_inputs_to_add:
            self._add_other_input(payslip, other_input, amount)
        payslip.compute_sheet()

        payslip_results = {'ALLOW': 1000.00, 'COMM': 800.00, 'ADV': 1500.00, 'LOAN': 1200.00, 'DED': -700.00, 'NET': 3800.00}
        self._validate_payslip(payslip, payslip_results)

    def test_salary_advance(self):
        instant_pay_structure = self.env.ref('l10n_ae_hr_payroll.l10n_ae_uae_instant_pay')
        uae_employee_structure = self.env.ref('l10n_ae_hr_payroll.uae_employee_payroll_structure')
        salary_advance_other_input = self.env.ref('l10n_ae_hr_payroll.l10n_ae_input_salary_advance')

        # First salary advance payslip of 500 on 01/09/2024 and setting the advance amount to 500 and validate the payslip
        test_saladv_payslip1 = self._generate_payslip(
            date(2024, 9, 1), date(2024, 9, 30), struct_id=instant_pay_structure.id
        )
        self._add_other_input(test_saladv_payslip1, salary_advance_other_input, 500)

        test_saladv_payslip1.compute_sheet()
        test_saladv_payslip1.action_payslip_done()

        # Second salary advance payslip of 200 on 15/09/2024
        test_saladv_payslip2 = self._generate_payslip(
            date(2024, 9, 15), date(2024, 9, 30), struct_id=instant_pay_structure.id
        )
        self._add_other_input(test_saladv_payslip2, salary_advance_other_input, 200)

        test_saladv_payslip2.compute_sheet()
        test_saladv_payslip2.action_payslip_done()

        # September monthly payslip
        test_payslip_sept = self._generate_payslip(
            date(2024, 9, 1), date(2024, 9, 30), struct_id=uae_employee_structure.id
        )
        test_payslip_sept._compute_input_line_ids()
        # September monthly pay should have salary advance recovery = 700 by default
        nbr_rec, amount_rec = self._get_input_line_amount(test_payslip_sept, "ADVREC")
        self.assertEqual(nbr_rec, 1)
        self.assertEqual(amount_rec, 700)
        # Changing the recovery amount to 500 and validate the payslip
        test_payslip_sept.input_line_ids.filtered(lambda line: line.code == "ADVREC").write({
            "amount": 500
        })
        test_payslip_sept.compute_sheet()
        test_payslip_sept.action_payslip_done()

        nbr_rec, amount_rec = self._get_input_line_amount(test_payslip_sept, "ADVREC")
        self.assertEqual(nbr_rec, 1)
        self.assertEqual(amount_rec, 500)

        # Third salary advance payslip of 300 on 1/10/2024
        test_saladv_payslip3 = self._generate_payslip(
            date(2024, 10, 1), date(2024, 10, 31), struct_id=instant_pay_structure.id
        )
        self._add_other_input(test_saladv_payslip3, salary_advance_other_input, 300)
        test_saladv_payslip3.compute_sheet()
        test_saladv_payslip3.action_payslip_done()

        # October monthly pay should have salary advance recovery = 500 (200+300) by default
        test_payslip_oct = self._generate_payslip(
            date(2024, 10, 1), date(2024, 10, 31), struct_id=uae_employee_structure.id
        )
        test_payslip_oct._compute_input_line_ids()
        test_payslip_oct.compute_sheet()
        test_payslip_oct.action_payslip_done()

        nbr_rec, amount_rec = self._get_input_line_amount(test_payslip_oct, "ADVREC")
        self.assertEqual(nbr_rec, 1)
        self.assertEqual(amount_rec, 500)

        # November monthly pay should have salary advance recovery = 0
        test_payslip_nov = self._generate_payslip(
            date(2024, 11, 1), date(2024, 11, 30), struct_id=uae_employee_structure.id
        )
        test_payslip_nov._compute_input_line_ids()
        test_payslip_nov.compute_sheet()
        test_payslip_nov.action_payslip_done()
        nbr_rec, amount_rec = self._get_input_line_amount(test_payslip_nov, "ADVREC")
        self.assertEqual(nbr_rec, 0)
        self.assertEqual(amount_rec, 0)

    def test_end_of_service_salary_rule_1(self):
        """
        Test the end of service salary rule calculation.
        The rule should consider the full 30 days compensation after completing the 6th year, not the 5th.
        """
        employee_1 = self.env['hr.employee'].create({
            'name': 'Test Employee 1',
            'contract_date_start': date(2014, 6, 4),
            'date_version': date(2014, 6, 4),
            'wage': 15_000.0,
        })

        departure_notice_1 = self.env['hr.departure.wizard'].create({
            'employee_ids': [Command.link(employee_1.id)],
            'departure_date': date(2017, 2, 19),
            'departure_description': 'foo',
            'set_date_end': True,
        })
        departure_notice_1.with_context(employee_termination=True).action_register_departure()

        payslip_1 = self._generate_payslip(
            date(2017, 2, 1),
            date(2017, 2, 28),
            employee_id=employee_1.id,
            version_id=employee_1.version_id.id,
        )

        self.assertEqual(payslip_1._get_line_values(['EOS'])['EOS'][payslip_1.id]['total'], 28_432.0, "End of Service calculation is incorrect")

    def test_end_of_service_salary_rule_2(self):
        employee_2 = self.env['hr.employee'].create({
            'name': 'Test Employee 2',
            'contract_date_start': date(2019, 7, 22),
            'date_version': date(2019, 7, 22),
            'wage': 15_000.0,
        })

        departure_notice_2 = self.env['hr.departure.wizard'].create({
            'employee_ids': [Command.link(employee_2.id)],
            'departure_date': date(2025, 1, 8),
            'departure_description': 'foo',
            'set_date_end': True,
        })
        departure_notice_2.with_context(employee_termination=True).action_register_departure()

        payslip_2 = self._generate_payslip(
            date(2025, 1, 1),
            date(2025, 1, 31),
            employee_id=employee_2.id,
            version_id=employee_2.version_id.id,
        )

        self.assertEqual(payslip_2._get_line_values(['EOS'])['EOS'][payslip_2.id]['total'], 57_365.0, "End of Service calculation is incorrect")

    def test_end_of_service_salary_rule_3(self):
        employee_3 = self.env['hr.employee'].create({
            'name': 'Test Employee 3',
            'contract_date_start': date(2018, 7, 22),
            'date_version': date(2018, 7, 22),
            'wage': 15_000.0,
        })

        departure_notice_3 = self.env['hr.departure.wizard'].create({
            'employee_ids': [Command.link(employee_3.id)],
            'departure_date': date(2025, 1, 8),
            'departure_description': 'foo',
            'set_date_end': True,
        })
        departure_notice_3.with_context(employee_termination=True).action_register_departure()

        payslip_3 = self._generate_payslip(
            date(2025, 1, 1),
            date(2025, 1, 31),
            employee_id=employee_3.id,
            version_id=employee_3.version_id.id,
        )

        self.assertEqual(payslip_3._get_line_values(['EOS'])['EOS'][payslip_3.id]['total'], 74_449.0, "End of Service calculation is incorrect")

    def test_payslip_attendance_1(self):
        if self.env['ir.module.module']._get('hr_payroll_attendance').state != 'installed':
            self.skipTest("Skipping test because hr_payroll_attendance is not installed.")

        self.employee.country_id = False
        self.contract.write({
            'contract_date_start': '2025-01-01',
            'work_entry_source': 'attendance',
            'wage': 5000,
            'wage_type': 'monthly',
            'l10n_ae_housing_allowance': 2000,
            'l10n_ae_transportation_allowance': 1000,
            'l10n_ae_other_allowances': 100,
            'l10n_ae_is_dews_applied': False,
        })

        worked_days_vals = [
            {'name': 'Unpaid', 'code': 'LEAVE90', 'number_of_hours': 16, 'number_of_days': 2},
            {'name': 'Paid Time Off', 'code': 'LEAVE120', 'number_of_hours': 24, 'number_of_days': 3},
            {'name': 'Sick Leave 50', 'code': 'AESICKLEAVE50', 'number_of_hours': 24, 'number_of_days': 3},
            {'name': 'Out of Contract', 'code': 'OUT', 'number_of_hours': 32, 'number_of_days': 4},
            {'name': 'Attendance', 'code': 'WORK100', 'number_of_hours': 88, 'number_of_days': 11},
        ]

        payslip = self._generate_payslip('2025-07-01', '2025-07-31')
        payslip.write({
            "worked_days_line_ids": [self._create_worked_days(**vals) for vals in worked_days_vals],
        })
        payslip.compute_sheet()
        payslip_results = {
            'BASIC': 2391.30,
            'HOUALLOW': 956.52,
            'TRAALLOW': 478.26,
            'OTALLOW': 47.83,
            'EOSP': 188.73,
            'ALP': 436.76,
            'AEPAID': 1056.48,
            'AESPAID50': 528.24,
            'GROSS': 5458.63,
            'NET': 5458.63,
        }
        self._validate_payslip(payslip, payslip_results)

    def test_payslip_attendance_2(self):
        if self.env['ir.module.module']._get('hr_payroll_attendance').state != 'installed':
            self.skipTest("Skipping test because hr_payroll_attendance is not installed.")

        self.employee.country_id = False
        self.contract.write({
            'contract_date_start': '2025-01-01',
            'work_entry_source': 'attendance',
            'wage': 5000,
            'hourly_wage': 44.02,
            'wage_type': 'hourly',
            'l10n_ae_housing_allowance': 2000,
            'l10n_ae_transportation_allowance': 1000,
            'l10n_ae_other_allowances': 100,
            'l10n_ae_is_dews_applied': False,
        })

        worked_days_vals = [
            {'name': 'Unpaid', 'code': 'LEAVE90', 'number_of_hours': 16, 'number_of_days': 2},
            {'name': 'Paid Time Off', 'code': 'LEAVE120', 'number_of_hours': 24, 'number_of_days': 3},
            {'name': 'Sick Leave 50', 'code': 'AESICKLEAVE50', 'number_of_hours': 24, 'number_of_days': 3},
            {'name': 'Out of Contract', 'code': 'OUT', 'number_of_hours': 32, 'number_of_days': 4},
            {'name': 'Attendance', 'code': 'WORK100', 'number_of_hours': 88, 'number_of_days': 11},
        ]

        payslip = self._generate_payslip('2025-06-01', '2025-06-30')
        payslip.write({
            "worked_days_line_ids": [self._create_worked_days(**vals) for vals in worked_days_vals]
        })
        payslip.compute_sheet()
        payslip_results = {
            'BASIC': 2391.30,
            'EOSP': 188.73,
            'ALP': 436.76,
            'AEPAID': 1056.48,
            'AESPAID50': 528.24,
            'GROSS': 3976.02,
            'NET': 3976.02,
        }
        self._validate_payslip(payslip, payslip_results)
