# Part of Odoo. See LICENSE file for full copyright and licensing details.

import datetime

from odoo import Command
from odoo.addons.hr_payroll.tests.common import TestPayslipBase
from odoo.exceptions import UserError
from odoo.tests import Form
from dateutil.relativedelta import relativedelta


class TestPayslipFlow(TestPayslipBase):

    def test_00_payslip_flow(self):
        """ Testing payslip flow and report printing """

        # I create an employee Payslip
        richard_payslip = self.env['hr.payslip'].create({
            'name': 'Payslip of Richard',
            'employee_id': self.richard_emp.id,
        })

        payslip_input = self.env['hr.payslip.input'].search([('payslip_id', '=', richard_payslip.id)])
        # I assign the amount to Input data
        payslip_input.write({'amount': 5.0})

        # I verify the payslip is in draft state
        self.assertEqual(richard_payslip.state, 'draft', 'State not changed!')

        richard_payslip.compute_sheet()

        # Then I click on the 'Confirm' button on payslip
        richard_payslip.action_payslip_done()

        # I verify that the payslip is in validated state
        self.assertEqual(richard_payslip.state, 'validated', 'State not changed!')

        # Then I click on the 'Mark as paid' button on payslip
        richard_payslip.action_payslip_paid()

        # I verify that the payslip is in paid state
        self.assertEqual(richard_payslip.state, 'paid', 'State not changed!')

        # I want to check refund payslip so I click on refund button.
        richard_payslip.refund_sheet()

        # I check on new payslip Credit Note is checked or not.
        payslip_refund = self.env['hr.payslip'].search([('name', 'like', 'Refund: '+ richard_payslip.name), ('credit_note', '=', True)])
        self.assertTrue(bool(payslip_refund), "Payslip not refunded!")

        # I want to generate a payslip from Payslip run.
        payslip_run = self.env['hr.payslip.run'].create({
            'date_end': '2011-09-30',
            'date_start': '2011-09-01',
            'name': 'Payslip for Employee'
        })

        # I create record for generating the payslip for this Payslip run.

        # The contract of Richard starts in 2018, the payrun is for 2011, no valid versions can be found.
        # So the generate_payslip without versions must raise an error
        with self.assertRaises(UserError):
            payslip_run.generate_payslips(employee_ids=[self.richard_emp.id])

    def test_01_batch_with_specific_structure(self):
        """ Generate payslips for the employee whose running contract is based on the same Salary Structure Type"""

        specific_structure_type = self.env['hr.payroll.structure.type'].create({
            'name': 'Structure Type Test'
        })

        specific_structure = self.env['hr.payroll.structure'].create({
            'name': 'End of the Year Bonus - Test',
            'type_id': specific_structure_type.id,
        })

        # 13th month pay
        payslip_run = self.env['hr.payslip.run'].create({
            'date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'date_end': datetime.date.today() + relativedelta(years=-1, month=8, day=31),
            'structure_id': specific_structure.id,
            'name': 'End of the year bonus',
        })

        with self.assertRaises(UserError):
            payslip_run.generate_payslips(payslip_run._get_valid_version_ids())

        # Update the structure type and generate payslips again
        specific_structure_type.default_struct_id = specific_structure.id
        self.richard_emp.version_ids[0].structure_type_id = specific_structure_type.id

        payslip_run = self.env['hr.payslip.run'].create({
            'date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'date_end': datetime.date.today() + relativedelta(years=-1, month=8, day=31),
            'structure_id': specific_structure.id,
            'name': 'Batch for Structure',
        })

        payslip_run.generate_payslips(payslip_run._get_valid_version_ids())

        self.richard_emp.structure_type_id = specific_structure_type.id

        self.assertTrue(payslip_run.slip_ids)
        self.assertTrue(self.richard_emp.id in payslip_run.slip_ids.employee_id.ids)

        self.assertEqual(len(payslip_run.slip_ids), 1)
        self.assertEqual(payslip_run.slip_ids.struct_id.id, specific_structure.id)

    def test_02_payslip_batch_with_archived_employee(self):
        # archive his contact
        self.richard_emp.action_archive()

        # 13th month pay
        payslip_run = self.env['hr.payslip.run'].create({
            'date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'date_end': datetime.date.today() + relativedelta(years=-1, month=8, day=31),
            'name': 'End of the year bonus'
        })
        # I create record for generating the payslip for this Payslip run.
        payslip_run.generate_payslips(employee_ids=[self.richard_emp.id])

        self.assertEqual(len(payslip_run.slip_ids), 1)

    def test_03_payslip_batch_with_payment_process(self):
        '''
            Test to check if some payslips in the batch are already paid,
            the batch status can be updated to 'paid' without affecting
            those already paid payslips.
        '''
        self.contract_jules = self.jules_emp.version_id.write({
            'date_version': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'contract_date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'name': 'Contract for Jules',
            'wage': 5000.33,
            'employee_id': self.jules_emp.id,
            'structure_type_id': self.structure_type.id,
        })

        payslip_run = self.env['hr.payslip.run'].create({
            'date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'date_end': datetime.date.today() + relativedelta(years=-1, month=8, day=31),
            'name': 'Payment Test',
        })

        payslip_run.generate_payslips(employee_ids=[self.richard_emp.id, self.jules_emp.id])

        payslip_run.action_validate()

        self.assertEqual(len(payslip_run.slip_ids), 2)
        self.assertTrue(all(payslip.state == 'validated' for payslip in payslip_run.slip_ids), 'State not changed!')

        # Mark the first payslip as paid and store the paid date
        payslip_run.slip_ids[0].action_payslip_paid()
        paid_date = payslip_run.slip_ids[0].paid_date

        self.assertEqual(payslip_run.slip_ids[0].state, 'paid', 'State not changed!')
        self.assertEqual(payslip_run.slip_ids[1].state, 'validated', 'State not changed!')

        payslip_run.action_paid()

        self.assertEqual(payslip_run.state, '03_paid', 'State not changed!')
        self.assertTrue(all(payslip.state == 'paid' for payslip in payslip_run.slip_ids), 'State not changed!')
        self.assertEqual(payslip_run.slip_ids[0].paid_date, paid_date, 'payslip paid date should not be changed')

    def test_04_payslip_batch_wizard_for_employee_selection_mode(self):
        '''
            Test employee_ids selection in batch payslip generating wizard
            based on employee selection mode fields
        '''
        self.richard_emp.version_ids[0].contract_date_end = False
        self.contract_jules = self.jules_emp.version_id.write({
            'date_version': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'contract_date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'name': 'Contract for Jules',
            'wage': 5000.33,
            'employee_id': self.jules_emp.id,
        })

        payslip_run = self.env['hr.payslip.run'].create({
            'date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'date_end': datetime.date.today() + relativedelta(years=-1, month=8, day=31),
            'name': 'Payment Test',
        })

        payslip_run.generate_payslips(employee_ids=[self.richard_emp.id, self.jules_emp.id])

        self.assertEqual(len(payslip_run.slip_ids.employee_id.ids), 2)
        self.assertTrue(all(employee in [self.richard_emp.id, self.jules_emp.id] for employee in payslip_run.slip_ids.employee_id.ids))

    def test_05_payslip_batch_wizard_for_department_selection_mode(self):
        '''
            Test employee_ids selection in batch payslip generating wizard
            based on department selection mode fields
        '''
        self.richard_emp.version_ids[0].date_end = False
        self.contract_jules = self.jules_emp.version_id.write({
            'date_version': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'contract_date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'name': 'Contract for Jules',
            'wage': 5000.33,
            'employee_id': self.jules_emp.id,
        })
        self.richard_emp.department_id = False

        payslip_run = self.env['hr.payslip.run'].create({
            'date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'date_end': datetime.date.today() + relativedelta(years=-1, month=8, day=31),
            'name': 'Payment Test',
        })

        employees = self.env["hr.employee"].search([('department_id', 'in', [self.dep_rd.id])])

        payslip_run.generate_payslips(employee_ids=employees.ids)

        self.assertEqual(len(employees.ids), 1)
        self.assertEqual(employees.ids[0], self.jules_emp.id)

    def test_06_payslip_batch_wizard_for_job_selection_mode(self):
        '''
            Test employee_ids selection in batch payslip generating wizard
            based on job selection mode fields
        '''
        self.richard_emp.version_ids[0].date_end = False
        job_developer = self.env['hr.job'].create({
            'name': 'Experienced Developer',
            'department_id': self.dep_rd.id,
            'no_of_recruitment': 5,
        })
        self.richard_emp.job_id = job_developer.id

        payslip_run = self.env['hr.payslip.run'].create({
            'date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'date_end': datetime.date.today() + relativedelta(years=-1, month=8, day=31),
            'name': 'Payment Test',
        })

        employees = self.env["hr.employee"].search([('job_id', 'in', [job_developer.id])])

        payslip_run.generate_payslips(employee_ids=employees.ids)

        self.assertEqual(len(employees.ids), 1)
        self.assertTrue(self.richard_emp in employees)

    def test_07_payslip_batch_wizard_for_category_selection_mode(self):
        '''
            Test employee_ids selection in batch payslip generating wizard
            based on category selection mode fields
        '''
        self.richard_emp.version_ids[0].date_end = False
        self.contract_jules = self.jules_emp.version_id.write({
            'date_version': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'contract_date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'name': 'Contract for Jules',
            'wage': 5000.33,
            'employee_id': self.jules_emp.id,
        })
        category_tag = self.env['hr.employee.category'].create({'name': 'Test category'})
        self.jules_emp.category_ids = [category_tag.id]

        payslip_run = self.env['hr.payslip.run'].create({
            'date_start': datetime.date.today() + relativedelta(years=-1, month=8, day=1),
            'date_end': datetime.date.today() + relativedelta(years=-1, month=8, day=31),
            'name': 'Payment Test',
        })

        employees = self.env["hr.employee"].search([('category_ids', 'in', [category_tag.id])])

        payslip_run.generate_payslips(employee_ids=employees.ids)

        self.assertEqual(len(employees.ids), 1)
        self.assertEqual(employees.ids[0], self.jules_emp.id)

    def test_08_payslip_batch_wizard_for_structure_type_selection_mode_with_multiple_contract(self):
        structure_typeA, structure_typeB = self.env['hr.payroll.structure.type'].create([
            {'name': 'Test A'},
            {'name': 'Test B'},
        ])

        structureA, structureB = self.env['hr.payroll.structure'].create([
            {
                'name': 'Test structure A',
                'type_id': structure_typeA.id,
            },
            {
                'name': 'Test structure B',
                'type_id': structure_typeB.id,
            },
        ])

        payslip_runA, payslip_runB, payslip_runC = self.env['hr.payslip.run'].create([
            {
                'date_start': datetime.date.today() + relativedelta(years=-1, month=2, day=1),
                'date_end': datetime.date.today() + relativedelta(years=-1, month=2, day=31),
                'structure_id': structureA.id,
                'name': 'Payslip RUN A'
            },
            {
                'date_start': datetime.date.today() + relativedelta(years=-1, month=4, day=1),
                'date_end': datetime.date.today() + relativedelta(years=-1, month=4, day=31),
                'structure_id': structureB.id,
                'name': 'Payslip RUN B'
            },
            {
                'date_start': datetime.date.today() + relativedelta(years=-1, month=3, day=1),
                'date_end': datetime.date.today() + relativedelta(years=-1, month=3, day=31),
                'structure_id': structureB.id,
                'name': 'Payslip RUN C'
            },
        ])

        employee_timmy, employee_gerard, employee_michel = self.env['hr.employee'].create([
            {
                'name': 'Timmy',
                'sex': 'male',
                'birthday': '1984-05-01',
                'date_version': datetime.date.today() + relativedelta(years=-1, month=1, day=1),
                'contract_date_start': datetime.date.today() + relativedelta(years=-1, month=1, day=1),
                'contract_date_end': datetime.date.today() + relativedelta(years=-1, month=3, day=15),
                'wage': 5000.33,
                'structure_type_id': structure_typeA.id,
            },
            {
                'name': 'Gerard',
                'sex': 'male',
                'birthday': '1964-01-23',
                'date_version': datetime.date.today() + relativedelta(years=-1, month=1, day=1),
                'contract_date_start': datetime.date.today() + relativedelta(years=-1, month=1, day=1),
                'wage': 5000.33,
                'structure_type_id': structure_typeA.id,
            },
            {
                'name': 'Michel',
                'sex': 'male',
                'birthday': '1975-10-06',
                'date_version': datetime.date.today() + relativedelta(years=-1, month=1, day=1),
                'contract_date_start': datetime.date.today() + relativedelta(years=-1, month=1, day=1),
                'wage': 7000.33,
                'structure_type_id': structure_typeB.id,
            },
        ])

        employee_timmy.create_version({
            'date_version': datetime.date.today() + relativedelta(years=-1, month=3, day=16),
            'contract_date_start': datetime.date.today() + relativedelta(years=-1, month=3, day=16),
            'contract_date_end': datetime.date.today() + relativedelta(years=1, month=3, day=31),
            'wage': 7000.33,
            'employee_id': employee_timmy.id,
            'structure_type_id': structure_typeB.id,
        })

        # Batch A for only structure A
        # For february YEAR-1
        # Expected employees/contracts
        # Timmy  contract A (YEAR-1/01/01 -> YEAR-1/03/15)
        # Gerard contract A (YEAR-1/01/01 -> no end date )
        payslip_runA.generate_payslips(payslip_runA._get_valid_version_ids())
        self.assertEqual(len(payslip_runA.slip_ids.employee_id.ids), 2)
        self.assertEqual(len(payslip_runA.slip_ids.ids), 2)
        self.assertTrue(all(
            payslip.version_id.structure_type_id == payslip.struct_id.type_id and
            payslip.struct_id.type_id == payslip_runA.structure_id.type_id
        for payslip in payslip_runA.slip_ids))

        # Batch B for only structure B
        # For april YEAR-1
        # Expected employees/contracts
        # Timmy  contract B (YEAR-1/03/16 -> no end date)
        # Michel contract B (YEAR-1/01/01 -> no end date)
        payslip_runB.generate_payslips(payslip_runB._get_valid_version_ids())
        self.assertEqual(len(payslip_runB.slip_ids.employee_id.ids), 2)
        self.assertEqual(len(payslip_runB.slip_ids.ids), 2)
        self.assertTrue(all(
            payslip.version_id.structure_type_id == payslip.struct_id.type_id and
            payslip.struct_id.type_id == payslip_runB.structure_id.type_id
        for payslip in payslip_runB.slip_ids))

        # Batch C for two structures
        # For march YEAR-1
        # Expected employees/contracts
        # Timmy| contract A (YEAR-1/01/01 -> YEAR-1/03/15)
        #      | contract B (YEAR-1/03/16 -> no end date )
        # Gerard contract A (YEAR-1/01/01 -> no end date )
        # Michel contract B (YEAR-1/01/01 -> no end date )
        payslip_runC.generate_payslips(payslip_runC._get_valid_version_ids())
        self.assertEqual(len(payslip_runC.slip_ids.employee_id.ids), 2)
        self.assertEqual(len(payslip_runC.slip_ids.ids), 2)
        self.assertTrue(all(
            payslip.version_id.structure_type_id == payslip.struct_id.type_id and
            payslip.struct_id.type_id == payslip_runC.structure_id.type_id
        for payslip in payslip_runC.slip_ids))

    def test_09_payslip_creation_with_employee_without_contract(self):
        employee = self.env['hr.employee'].create({
            'name': 'Johnny',
        })
        payslip_form = Form(self.env['hr.payslip'])
        payslip_form.employee_id = employee
        payslip_form.save()
        self.assertTrue(payslip_form)
