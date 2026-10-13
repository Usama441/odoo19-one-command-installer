from odoo.addons.account.tests.common import AccountTestInvoicingCommon
from odoo.tests import tagged


@tagged('post_install_l10n', 'post_install', '-at_install')
class TestL10nGtEdi(AccountTestInvoicingCommon):

    @classmethod
    @AccountTestInvoicingCommon.setup_country('gt')
    def setUpClass(cls):
        super().setUpClass()
        ChartTemplate = cls.env['account.chart.template']

        # ==== Taxes ====
        cls.iva_withholding = ChartTemplate.ref('tax_vat_withhold')
        cls.isr_withholding = ChartTemplate.ref('tax_isr_withhold')

    def test_fesp_vendor_bill_report_values_with_withholding_taxes(self):
        bill = self._create_invoice_one_line(
            move_type='in_invoice',
            product_id=self.product_a,
            tax_ids=self.iva_withholding | self.isr_withholding,
            l10n_gt_edi_doc_type='FESP',
        )
        bill.action_post()

        self.env['l10n_gt_edi.document'].create({'invoice_id': bill.id, 'state': 'invoice_sent'})
        values = bill._l10n_gt_edi_get_extra_invoice_report_values()

        self.assertIn('gran_total', values)
        self.assertIn('retencion_gran_total', values)

    def test_nabn_available_only_for_vendor_credit_note(self):
        vendor_bill = self._create_invoice(move_type='in_invoice', company_id=self.company.id)
        vendor_bill_types = set(vendor_bill.l10n_gt_edi_available_doc_types.split(','))
        self.assertNotIn('NABN', vendor_bill_types)

        vendor_credit_note = self._create_invoice(move_type='in_refund', company_id=self.company.id)
        vendor_credit_note_types = set(vendor_credit_note.l10n_gt_edi_available_doc_types.split(','))
        self.assertIn('NABN', vendor_credit_note_types)

    def test_nabn_reports_only_its_own_phrase(self):
        """Test that a NABN drops the phrases inherited from the company and reports the manually selected one."""
        company_phrase = self.env.ref('l10n_gt_edi.l10n_gt_edi_phrase_type_1_code_1')
        nabn_phrase = self.env.ref('l10n_gt_edi.l10n_gt_edi_phrase_type_9_code_16')
        self.company.l10n_gt_edi_phrase_ids = company_phrase

        credit_note = self._create_invoice_one_line(
            move_type='in_refund',
            product_id=self.product_a,
            l10n_gt_edi_doc_type='NCRE',
        )
        self.assertIn(company_phrase, credit_note.l10n_gt_edi_phrase_ids)

        credit_note.l10n_gt_edi_doc_type = 'NABN'
        self.assertFalse(credit_note.l10n_gt_edi_phrase_ids)

        credit_note.l10n_gt_edi_phrase_ids = nabn_phrase
        credit_note._compute_l10n_gt_edi_phrase_ids()  # the manual phrase survives a recompute
        self.assertEqual(credit_note.l10n_gt_edi_phrase_ids, nabn_phrase)

        gt_values = {}
        credit_note._l10n_gt_edi_add_base_values(gt_values)
        self.assertEqual(gt_values['frases'], [{'tipo_frase': 9, 'codigo_escenario': 16}])

    def test_purchase_document_types_not_filtered_by_affiliation(self):
        move = self._create_invoice(move_type='in_invoice', company_id=self.company.id)
        available_types = set(move.l10n_gt_edi_available_doc_types.split(','))
        self.assertIn('FPEQ', available_types)
        self.assertIn('FCAP', available_types)

    def test_credit_note_uses_original_invoice_date(self):
        """Test that the reference date for credit notes is the invoice_date of the original invoice."""

        invoice = self._create_invoice_one_line(
            move_type='out_invoice',
            product_id=self.product_a,
            invoice_date='2026-07-08',
            l10n_gt_edi_doc_type='FACT',
        )
        invoice.action_post()

        self.env['l10n_gt_edi.document'].create({
            'invoice_id': invoice.id,
            'state': 'invoice_sent',
            'datetime': '2026-07-17 07:42:31',
            'uuid': 'DEMO-UUID-1234',
            'serial_number': 'DEMO',
            'series': 'DEMO',
        })

        move_reversal = self.env['account.move.reversal'].with_context(active_model="account.move", active_ids=invoice.ids).create({
            'date': '2026-07-10',
            'reason': 'Test Reversal',
            'journal_id': invoice.journal_id.id,
        })
        reversal_action = move_reversal.refund_moves()
        credit_note = self.env['account.move'].browse(reversal_action['res_id'])
        credit_note.action_post()

        gt_values = {}
        credit_note._l10n_gt_edi_add_reference_values(gt_values)
        self.assertEqual(gt_values.get('referencias_fecha_emision_documento_origen'), '2026-07-08')

    def test_export_complement_on_export_doc_types(self):
        """Test that the export complement is sent for the invoice document types that allow exports."""
        self.partner_a.country_id = self.env.ref('base.us')
        invoice = self._create_invoice_one_line(product_id=self.product_a, l10n_gt_edi_doc_type='FACT')

        for doc_type in ('FACT', 'FCAM', 'FPEQ', 'FCAP'):
            with self.subTest(doc_type=doc_type):
                invoice.l10n_gt_edi_doc_type = doc_type
                gt_values = {}
                invoice._l10n_gt_edi_add_base_values(gt_values)
                self.assertEqual(gt_values['dte_exp'], 'SI')
                self.assertTrue(gt_values['have_exportacion'])

    def test_notes_copy_exp_from_export_invoice(self):
        """Test that NCRE and NDEB on an export invoice copy its 'Exp' without the export complement."""
        self.partner_a.country_id = self.env.ref('base.us')
        invoice = self._create_invoice_one_line(product_id=self.product_a, l10n_gt_edi_doc_type='FACT')
        credit_note = self._create_invoice_one_line(
            move_type='out_refund',
            product_id=self.product_a,
            reversed_entry_id=invoice.id,
            l10n_gt_edi_doc_type='NCRE',
        )
        debit_note = self._create_invoice_one_line(
            product_id=self.product_a,
            debit_origin_id=invoice.id,
            l10n_gt_edi_doc_type='NDEB',
        )

        for note in credit_note + debit_note:
            with self.subTest(doc_type=note.l10n_gt_edi_doc_type):
                gt_values = {}
                note._l10n_gt_edi_add_base_values(gt_values)
                self.assertEqual(gt_values['dte_exp'], 'SI')
                self.assertFalse(gt_values['have_exportacion'])
