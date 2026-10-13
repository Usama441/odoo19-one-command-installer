# Part of Odoo. See LICENSE file for full copyright and licensing details.

from unittest.mock import patch

from odoo.fields import Command
from odoo.exceptions import ValidationError
from odoo.tests.common import tagged
from odoo.addons.hr_payroll.tests.common import TestPayslipBase


@tagged('at_install', '-post_install')
class TestSalaryRule(TestPayslipBase):

    def test_python_rule_localdict_context(self):
        rule = self.env['hr.salary.rule'].create({
            'name': 'Rule using the computation context',
            'sequence': 6,
            'condition_select': 'python',
            'condition_python': """
localdict['condition_side_effect'] = True
result = localdict.get('condition_side_effect')
""",
            'amount_select': 'code',
            'amount_python_compute': """
localdict['amount_side_effect'] = 20.0
evaluation_side_effect = 22.0
result = localdict.get('amount_side_effect') + evaluation_side_effect
""",
            'code': 'TEST_LOCALDICT',
            'category_ids': [(4, self.env.ref('hr_payroll.ALW').id)],
            'struct_ids': [(4, self.developer_pay_structure.id)],
        })
        localdict = {}

        self.assertTrue(rule._satisfy_condition(localdict))
        self.assertTrue(localdict['condition_side_effect'])
        self.assertNotIn('localdict', localdict)

        amount, quantity, rate, _explanation_info = rule._compute_rule(localdict)
        self.assertEqual((amount, quantity, rate), (42.0, 1.0, 100.0))
        self.assertEqual(localdict['amount_side_effect'], 20.0)
        self.assertEqual(localdict['evaluation_side_effect'], 22.0)
        self.assertNotIn('localdict', localdict)

    def test_python_rule_batch_context(self):
        self.jules_emp.version_id.write({
            'date_version': '2018-01-01',
            'contract_date_start': '2018-01-01',
            'structure_type_id': self.structure_type.id,
            'wage': 3000.0,
        })
        rules = self.env['hr.salary.rule'].create([
            {
                'name': 'First round',
                'code': 'FIRST_ROUND',
                'round_of_computation': 0,
                'struct_ids': [Command.link(self.developer_pay_structure.id)],
                'condition_select': 'python',
                'condition_python': "result = 'localdict' not in localdict and 'localdicts' not in localdict",
                'amount_select': 'code',
                'amount_python_compute': """
round_amount = version.wage
localdict['round_values'] = {'amount': round_amount}
result = round_amount
""",
            },
            {
                'name': 'Second round',
                'code': 'SECOND_ROUND',
                'round_of_computation': 1,
                'struct_ids': [Command.link(self.developer_pay_structure.id)],
                'amount_select': 'code',
                'amount_python_compute': """
result = global_line_values['FIRST_ROUND'][payslip.id]['total'] + localdict['round_values']['amount'] + batch_amount
""",
            },
        ])
        self.developer_pay_structure.rule_ids = [Command.set(rules.ids)]
        payslips = self.env['hr.payslip'].create([
            {
                'employee_id': employee.id,
                'version_id': employee.version_id.id,
                'struct_id': self.developer_pay_structure.id,
                'date_from': '2026-08-01',
                'date_to': '2026-08-31',
            }
            for employee in self.richard_emp | self.jules_emp
        ])
        get_round_common_localdict = type(payslips)._get_round_common_localdict
        rounds = []

        def get_round_context(batch, round_nb, common_localdict):
            round_context = get_round_common_localdict(batch, round_nb, common_localdict)
            rounds.append(round_nb)
            if round_nb == 1:
                contexts = common_localdict['localdicts']
                self.assertEqual(set(contexts), set(payslips.ids))
                for context in contexts.values():
                    self.assertNotIn('localdict', context)
                    self.assertNotIn('localdicts', context)
                    line_values = context['global_line_values']['FIRST_ROUND']
                    payslip_id = context['payslip'].id
                    self.assertEqual(line_values[payslip_id]['total'], context['round_amount'])
                round_context['batch_amount'] = sum(context['round_amount'] for context in contexts.values())
                self.assertEqual(common_localdict['global_line_values']['FIRST_ROUND']['sum']['total'], round_context['batch_amount'])
            return round_context

        with patch.object(type(payslips), '_get_round_common_localdict', get_round_context):
            payslips.compute_sheet()

        self.assertEqual(rounds, [0, 1])
        batch_amount = sum(payslips.version_id.mapped('wage'))
        for payslip in payslips:
            lines = payslip.line_ids
            self.assertEqual(lines.filtered(lambda line: line.code == 'FIRST_ROUND').total, payslip.version_id.wage)
            self.assertAlmostEqual(
                lines.filtered(lambda line: line.code == 'SECOND_ROUND').total,
                2 * payslip.version_id.wage + batch_amount,
                places=2,
            )

    def test_unique_code_constraint(self):
        self.env['hr.salary.rule'].create({
            'name': 'Test Performance Bonus',
            'sequence': 6,
            'amount_select': 'fix',
            'amount_fix': 500,
            'code': 'TESTPB',
            'category_ids': [(4, self.env.ref('hr_payroll.ALW').id)],
            'struct_ids': [(4, self.developer_pay_structure.id)],
        })
        with self.assertRaises(ValidationError):
            self.env['hr.salary.rule'].create({
                'name': 'Test Performance Bonus Copy',
                'sequence': 6,
                'amount_select': 'fix',
                'amount_fix': 500,
                'code': 'TESTPB',
                'category_ids': [(4, self.env.ref('hr_payroll.ALW').id)],
                'struct_ids': [(4, self.developer_pay_structure.id)],
            })
