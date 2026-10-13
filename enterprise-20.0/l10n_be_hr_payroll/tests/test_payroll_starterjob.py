from datetime import date

from freezegun import freeze_time

from odoo.tests import tagged

from .common import TestPayrollCommon


@tagged('post_install_l10n', 'post_install', '-at_install', 'starterjob')
class TestPayrollStarterjob(TestPayrollCommon):

    def _compute_starterjob_payslip(self, birthday, date_from, date_to):
        employee = self.create_employee({
            'birthday': birthday,
            'date_version': date(2026, 1, 1),
            'contract_date_start': date(2026, 1, 1),
            'l10n_be_is_starterjob': True,
            'wage': 2500.0,
        })
        payslip = self.env['hr.payslip'].create({
            'employee_id': employee.id,
            'version_id': employee.version_id.id,
            'date_from': date_from,
            'date_to': date_to,
            'company_id': self.belgian_company.id,
        })
        payslip.compute_sheet()
        return payslip._get_line_values(['DED_STARTERJOB_SALARY', 'COMPSUPP'], compute_sum=True)

    @freeze_time('2026-10-05')
    def test_starterjob_age_at_payslip_period(self):
        # 20 at the end of September, 21 since October 3rd: the September payslip computed in October keeps the 6% reduction
        line_values = self._compute_starterjob_payslip(date(2005, 10, 3), date(2026, 9, 1), date(2026, 9, 30))
        self.assertAlmostEqual(line_values['DED_STARTERJOB_SALARY']['sum']['total'], -150.0, places=2)
        self.assertGreater(line_values['COMPSUPP']['sum']['total'], 0)

        # 17 today, 18 at the end of November: the November payslip computed in advance gets the 18% reduction
        line_values = self._compute_starterjob_payslip(date(2008, 11, 15), date(2026, 11, 1), date(2026, 11, 30))
        self.assertAlmostEqual(line_values['DED_STARTERJOB_SALARY']['sum']['total'], -450.0, places=2)
        self.assertGreater(line_values['COMPSUPP']['sum']['total'], 0)
