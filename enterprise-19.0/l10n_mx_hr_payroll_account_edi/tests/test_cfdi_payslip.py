# Part of Odoo. See LICENSE file for full copyright and licensing details.

import freezegun

from odoo.tests.common import tagged
from odoo.addons.l10n_mx_edi.tests.common import TestMxEdiCommon


@tagged('-at_install', 'post_install', 'post_install_l10n')
class TestMxEdiHrPayrollCommon(TestMxEdiCommon):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

    def check_cfdi_validity(self, payslip):
        self.assertTrue(payslip.l10n_mx_edi_document_ids)
        document = payslip.l10n_mx_edi_document_ids[0]
        self.assertEqual(document.state, 'payslip_sent', 'Sent failed with this error: %s' % document.message)

    @freezegun.freeze_time('2024-03-01')
    def test_cfdi_nomina(self):
        # TODO: test me post 19.0 freeze :)
        pass
        # employee = self.env['hr.employee'].create({
        #     'name': 'Employee',
        #     'company_id': self.company.id,
        #     'contract_date_start': '2024-01-01',
        #     'wage': '5000',
        #     'schedule_pay': 'bi-weekly',
        # })
        # payslip = self.env['hr.payslip'].create({
        #     'employee_id': employee.id,
        #     'name': 'Payslip',
        #     'date_from': '2024-05-09',
        #     'date_to': '2024-05-24',
        #     'struct_id': self.env.ref('l10n_mx_hr_payroll.l10n_mx_regular_pay').id,
        # })
        # payslip.compute_sheet()
        # payslip.action_payslip_done()
        # payslip.move_id.action_post()
        # self.check_cfdi_validity(payslip)
