# Part of Odoo. See LICENSE file for full copyright and licensing details.

from datetime import date

from odoo.addons.l10n_be_hr_payroll.tests.common import TestBelgiumCommon
from odoo.tests import tagged

from .test_payslip import TestPayslipBase


@tagged('post_install', '-at_install', 'commuting_fuel_card')
class TestCommutingFuelCard(TestPayslipBase, TestBelgiumCommon):

    def test_281_10_other_transport_without_fuel_card(self):
        """ The commuting fuel card is ordinary pay: box 14 (other means of transport) of the 281.10 declares
        the private car reimbursement paid beside it, not the card. """
        # The 281.10 generation requires a valid private address and NISS on the employee.
        self.employee.write({
            'niss': '/', 'l10n_be_legal_first_name': 'Test', 'l10n_be_legal_last_name': 'Employee',
            'private_street': 'Rue du Paradis 1', 'private_zip': '1000',
            'private_city': 'Brussels', 'private_country_id': self.env.ref('base.be').id,
        })
        # The 281.10 also requires that the company has street, zip, city, phone and VAT.
        self.env.company.write({
            'street': 'Rue du Paradis', 'zip': '6870', 'city': 'Eghezee', 'vat': 'BE0897223670', 'phone': '061928374',
        })
        self.update_version(date(2024, 9, 1))
        self.version.private_car_employee_kilometer = 10
        payslip = self.create_payslip(
            self.env.ref('l10n_be_hr_payroll.hr_payroll_structure_cp200_employee_salary'), date(2024, 9, 1), date(2024, 9, 30))
        payslip._set_input_value('FUEL_CARD_COMMUTE', 60)
        payslip.compute_sheet()
        line_values = payslip._get_line_values(['CAR.PRIV', 'FUEL_CARD_COMMUTE'])
        private_car = line_values['CAR.PRIV'][payslip.id]['total']
        self.assertTrue(private_car, "The private car reimbursement is paid beside the fuel card.")
        self.assertEqual(line_values['FUEL_CARD_COMMUTE'][payslip.id]['total'], 60)

        # Only validated or paid payslips are included in the 281.10 declaration.
        self.employee.write({'review_state': '1_reviewed'})
        payslip.action_payslip_done()
        declaration = self.env['l10n_be.281_xx'].create({'year': '2024'})
        employee_data = declaration.l10n_be_281_10_ids._get_rendering_data(self.employee)['employees_data'][0]
        self.assertAlmostEqual(
            employee_data['f10_2088_andervervoermiddel'], private_car, places=2,
            msg="Box 14 declares the private car reimbursement only, the fuel card is taxed as pay.",
        )
