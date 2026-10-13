from datetime import UTC
from unittest.mock import patch
from zoneinfo import ZoneInfo
import requests

from freezegun import freeze_time
from lxml import etree
from markupsafe import Markup

from .common import TestL10nCoEdiPosCommon

from odoo import Command
from odoo.exceptions import UserError
from odoo.tests import tagged


@tagged('post_install_l10n', 'post_install', '-at_install')
class TestDianPos(TestL10nCoEdiPosCommon):
    _test_user_groups = None  # FIXME list needed groups

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        cls.default_pos_order_ui_data = {
            'pos_order_lines_ui_args': [(cls.product_a, 2)],
            'payments': [(cls.default_pos_payment_method, 2380.0)]
        }

    def _mock_get_status_zip_pos_order(self, order, response_file, response_code=200):
        with patch.object(requests, 'post', return_value=self._mocked_request(response_file, response_code)):
            order.l10n_co_edi_pos_document_ids._get_status_zip()

    def _send_test_set_async(self):
        self.config.company_id.write({
            'l10n_co_edi_test_environment': True,
            'l10n_co_edi_certification_process': True,
        })

        order = self._create_and_send_order(pos_order_ui_data=self.default_pos_order_ui_data, response_file_name='SendTestSetAsync.xml')
        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'zip_key': '42424242',
            'state': 'invoice_pending',
            'message': Markup("<p>Invoice is being processed by the DIAN.</p>"),
        }])
        self.assertEqual(order.l10n_co_edi_pos_dian_state, 'invoice_pending')
        return order

    def test_get_status_zip_warnings(self):
        """ SendTestSetAsync then GetStatusZip which returns warnings but the document is valid. """
        # Step 1: SendTestSetAsync
        order = self._send_test_set_async()
        # Step 2: GetStatusZip
        self._mock_get_status_zip_pos_order(order=order, response_file='GetStatusZip_warnings.xml')

        # checks on the document
        self.assertEqual(len(order.l10n_co_edi_pos_document_ids), 1)
        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'zip_key': '42424242',
            'state': 'invoice_accepted',
            'message': Markup(
                "<p>Procesado Correctamente.</p>"
                "<ul><li>Regla: FAJ44b, Notificación: Nit o Documento de Identificación BlaBlaBla.</li>"
                "<li>Regla: FAJ43b, Notificación: Nombre informado No corresponde al BlaBlaBla.</li></ul>"
            ),
        }])
        # checks on the invoice
        self.assertTrue(order.l10n_co_edi_pos_attachment_id)
        self.assertEqual(order.l10n_co_edi_pos_dian_state, 'invoice_accepted')

    def test_get_status_zip_habilitation(self):
        """ SendTestSetAsync then GetStatusZip which inform that they passed the habitation process. """
        # Step 1: SendTestSetAsync
        order = self._send_test_set_async()
        # Step 2: GetStatusZip
        self._mock_get_status_zip_pos_order(order, response_file='GetStatusZip_habilitation.xml')

        # checks on the document
        self.assertEqual(len(order.l10n_co_edi_pos_document_ids), 1)
        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'zip_key': '42424242',
            'state': 'invoice_rejected',
            'message': Markup("<p>Set de prueba con identificador 123456 se encuentra Aceptado.</p>"),
        }])
        # checks on the invoice
        self.assertFalse(order.l10n_co_edi_pos_attachment_id)
        self.assertEqual(order.l10n_co_edi_pos_dian_state, 'invoice_rejected')

    def test_get_status_zip_pending(self):
        """ SendTestSetAsync then GetStatusZip which responds 'Batch is being processed' (need to check again later)"""
        # Step 1: SendTestSetAsync
        order = self._send_test_set_async()
        # Step 2: GetStatusZip
        self._mock_get_status_zip_pos_order(order, response_file='GetStatusZip_pending.xml')

        # checks on the document
        self.assertEqual(len(order.l10n_co_edi_pos_document_ids), 1)
        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'zip_key': '42424242',
            'state': 'invoice_pending',
            'message': Markup("<p>Batch en proceso de validación.</p>"),
            'show_button_get_status': True,
        }])
        # checks on the invoice
        self.assertFalse(order.l10n_co_edi_pos_attachment_id)
        self.assertEqual(order.l10n_co_edi_pos_dian_state, 'invoice_pending')

        # Step 3: GetStatusZip again (this time the document is processed)
        self._mock_get_status_zip_pos_order(order, response_file='GetStatusZip_warnings.xml')

        # checks on the document
        self.assertEqual(len(order.l10n_co_edi_pos_document_ids), 1)
        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'zip_key': '42424242',
            'state': 'invoice_accepted',
            'message': Markup(
                "<p>Procesado Correctamente.</p>"
                "<ul><li>Regla: FAJ44b, Notificación: Nit o Documento de Identificación BlaBlaBla.</li>"
                "<li>Regla: FAJ43b, Notificación: Nombre informado No corresponde al BlaBlaBla.</li></ul>"
            ),
        }])
        # checks on the invoice
        self.assertTrue(order.l10n_co_edi_pos_attachment_id)
        self.assertEqual(order.l10n_co_edi_pos_dian_state, 'invoice_accepted')

    def test_send_bill_sync_warnings(self):
        """ SendBillSync returning warnings but the document is valid. """
        order = self._create_and_send_order(pos_order_ui_data=self.default_pos_order_ui_data, response_file_name='SendBillSync_warnings.xml')
        self.assertTrue(order.l10n_co_edi_pos_attachment_id)
        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'zip_key': False,
            'state': 'invoice_accepted',
            'message': Markup(
                "<p>Procesado Correctamente.</p>"
                "<ul><li>Regla: FAJ44b, Notificación: Nit o Documento de Identificación informado No BlaBlaBla.</li>"
                "<li>Regla: FAJ43b, Notificación: Nombre informado No corresponde al registrado en el BlaBlaBla.</li></ul>"
            ),
        }])

    def test_receipt_data_multiple_obligation_types(self):
        """ The receipt must list every obligation type of the company, not only one. """
        self.config.company_id.partner_id.l10n_co_edi_obligation_type_ids = [Command.set([
            self.env.ref('l10n_co_edi.obligation_type_12').id,
            self.env.ref('l10n_co_edi.obligation_type_14').id,
            self.env.ref('l10n_co_edi.obligation_type_22').id,
        ])]
        order = self._create_and_send_order(pos_order_ui_data=self.default_pos_order_ui_data, response_file_name='SendBillSync_warnings.xml')
        self.assertEqual(order.l10n_co_edi_pos_dian_state, 'invoice_accepted')
        self.assertEqual(
            order.l10n_co_edi_pos_receipt_data['before_footer']['obligation_type_description'],
            "Gran contribuyente, Autorretenedor, Agente de retención en el impuesto sobre las ventas",
        )

    def test_send_bill_sync_errors(self):
        """ SendBillSync returning errors blocking the Send & Print flow. """
        error_raised = False
        try:
            self._create_and_send_order(pos_order_ui_data=self.default_pos_order_ui_data, response_file_name='SendBillSync_errors.xml')
        except UserError as e:
            error_raised = True
            self.assertEqual(e.args[0], "Error(s) when sending the document to the DIAN:\n"
                                        "- Regla: ZB01, Rechazo: Fallo en el esquema XML del archivo")

        self.assertTrue(error_raised)
        order = self.config.session_ids.order_ids[0]
        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'zip_key': False,
            'state': 'invoice_rejected',
            'message': Markup(
                "<p>Documento con errores en campos mandatorios.</p>"
                "<ul><li>Regla: ZB01, Rechazo: Fallo en el esquema XML del archivo</li></ul>"
            ),
        }])

        return order

    def test_send_bill_sync_errors_nsmap(self):
        """ SendBillSync returning errors due to a missing namespace, blocking the Send & Print flow. """
        error_raised = False
        try:
            self._create_and_send_order(pos_order_ui_data=self.default_pos_order_ui_data, response_file_name='SendBillSync_errors_nsmap.xml')
        except UserError as e:
            error_raised = True
            self.assertEqual(e.args[0], "Error(s) when sending the document to the DIAN:\n- Error al parsear xml. Namespace prefix 'sts' is not defined.")

        self.assertTrue(error_raised)
        order = self.config.session_ids.order_ids[0]
        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'zip_key': False,
            'state': 'invoice_rejected',
            'message': Markup("<p>Error al parsear xml. Namespace prefix 'sts' is not defined.</p>"),
        }])

    def test_send_bill_sync_duplicated(self):
        """ SendBillSync returning 'Regla: 90, Rechazo: Documento procesado anteriormente.'
        This means an invoice with the same CUFE has already been accepted by the DIAN.
        """
        error_raised = False
        try:
            self._create_and_send_order(pos_order_ui_data=self.default_pos_order_ui_data, response_file_name='SendBillSync_duplicated.xml')
        except UserError as e:
            error_raised = True
            self.assertEqual(e.args[0], "Error(s) when sending the document to the DIAN:\n"
                                        "- Regla: 90, Rechazo: Documento procesado anteriormente.")

        self.assertTrue(error_raised)
        order = self.config.session_ids.order_ids[0]
        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'zip_key': False,
            'state': 'invoice_rejected',
            'message': Markup(
                "<p>Validación contiene errores en campos mandatorios.</p>"
                "<ul><li>Regla: 90, Rechazo: Documento procesado anteriormente.</li></ul>"
            ),
        }])

    def _get_dian_signature(self, xml):
        doc = etree.fromstring(xml) if isinstance(xml, bytes) else xml
        return (
            doc.findtext('./{*}ID'),
            doc.findtext('.//{*}PayableAmount'),
            doc.findtext('.//{*}AccountingSupplierParty//{*}CompanyID'),
            doc.findtext('.//{*}AccountingCustomerParty//{*}CompanyID'),
        )

    def _order_issue_date(self, order):
        return order.date_order.replace(tzinfo=UTC).astimezone(ZoneInfo('America/Bogota')).date().isoformat()

    def _build_dian_xml(self, doc_id, amount, supplier_id, customer_id, issue_date, uuid='cufe_of_the_previously_accepted_invoice'):
        return f"""<Invoice>
            <ID>{doc_id}</ID>
            <UUID>{uuid}</UUID>
            <IssueDate>{issue_date}</IssueDate>
            <SigningTime>2025-02-28T19:00:00+00:00</SigningTime>
            <AccountingSupplierParty><Party><PartyTaxScheme><CompanyID>{supplier_id}</CompanyID></PartyTaxScheme></Party></AccountingSupplierParty>
            <AccountingCustomerParty><Party><PartyTaxScheme><CompanyID>{customer_id}</CompanyID></PartyTaxScheme></Party></AccountingCustomerParty>
            <LegalMonetaryTotal><PayableAmount>{amount}</PayableAmount></LegalMonetaryTotal>
        </Invoice>""".encode()

    def test_send_bill_sync_duplicated_matches_own_cufe(self):
        """ SendBillSync returning 'Regla: 90, Rechazo: Documento procesado anteriormente.'
        The render is anchored on the order's date_order (not wall-clock "now"), so retrying
        the same order later still recomputes the exact same CUFE. If DIAN's "already
        processed" identifier matches that CUFE, the order is recovered directly, with no
        extra lookup.
        """
        with freeze_time('2025-03-01 00:00:00'):
            # 1st attempt: rejected for an unrelated reason, so the order isn't accepted yet.
            # The CUFE DIAN actually has (as if this first send had been accepted) is captured
            # here, anchored on this instant.
            order = self.test_send_bill_sync_errors()

            outgoing_xml, errors = self.env['pos.edi.xml.ubl_dian']._export_pos_order(order)
            self.assertFalse(errors)
            own_cufe = etree.fromstring(outgoing_xml).findtext('./{*}UUID')

        duplicated_response = self.file_read('l10n_co_edi/tests/responses/SendBillSync_duplicated.xml').decode().replace(
            'cufe_of_the_previously_accepted_invoice', own_cufe,
        )

        # 2nd attempt, several minutes later: DIAN reports the document (referenced by our own
        # CUFE) as already processed.
        with (
            freeze_time('2025-03-01 00:05:00'),
            self._mock_get_status(),
            patch(f'{self.utils_path}._build_and_send_request', return_value={'response': duplicated_response, 'status_code': 200}),
        ):
            order.l10n_co_edi_pos_action_send_document()

        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'identifier': own_cufe,
            'state': 'invoice_accepted',
        }])
        self.assertEqual(order.l10n_co_edi_pos_dian_state, 'invoice_accepted')

    def test_send_bill_sync_duplicated_fallback_matches(self):
        """ Same 'already processed' response, but referencing a CUFE that doesn't match our own
        render (e.g. the order was first sent before the date_order-anchoring fix, under a CUFE
        computed from a since-unreproducible timestamp). The fetched DIAN document's ID, amount,
        both parties' CompanyID and issue date (matched against the order's own date_order, not
        the unreliable render) still match ours, so it must be recovered.
        """
        order = self.test_send_bill_sync_errors()  # 1st attempt: rejected for an unrelated reason

        outgoing_xml, errors = self.env['pos.edi.xml.ubl_dian']._export_pos_order(order)
        self.assertFalse(errors)
        matching_dian_xml = self._build_dian_xml(*self._get_dian_signature(outgoing_xml), issue_date=self._order_issue_date(order))

        # 2nd attempt: DIAN reports the document as already processed, under a CUFE that
        # doesn't match ours, but GetXmlByDocumentKey returns a document matching on the
        # more stable invariants (ID, amount, both parties, issue date)
        with (
            self.patched_document('_get_xml_by_document_key_for_company', matching_dian_xml),
            self._mock_get_status(),
            patch(f'{self.utils_path}._build_and_send_request', return_value=self._mocked_response('SendBillSync_duplicated.xml', 200)),
        ):
            order.l10n_co_edi_pos_action_send_document()

        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'identifier': 'cufe_of_the_previously_accepted_invoice',
            'state': 'invoice_accepted',
        }])
        self.assertEqual(order.l10n_co_edi_pos_dian_state, 'invoice_accepted')
        # the stored attachment must be DIAN's document, not our own (un-accepted) render,
        # so its own cbc:UUID matches document.identifier instead of contradicting it
        self.assertEqual(order.l10n_co_edi_pos_attachment_id.raw.content, matching_dian_xml)

    def test_send_bill_sync_duplicated_fallback_no_match(self):
        """ Same as above, but the fetched DIAN document has a different amount, so it must
        stay rejected instead of being wrongly recovered.
        """
        order = self.test_send_bill_sync_errors()  # 1st attempt: rejected for an unrelated reason

        outgoing_xml, errors = self.env['pos.edi.xml.ubl_dian']._export_pos_order(order)
        self.assertFalse(errors)
        doc_id, _amount, supplier_id, customer_id = self._get_dian_signature(outgoing_xml)
        mismatching_dian_xml = self._build_dian_xml(doc_id, '999999.99', supplier_id, customer_id, issue_date=self._order_issue_date(order))

        with (
            self.patched_document('_get_xml_by_document_key_for_company', mismatching_dian_xml),
            self._mock_get_status(),
            patch(f'{self.utils_path}._build_and_send_request', return_value=self._mocked_response('SendBillSync_duplicated.xml', 200)),
            self.assertRaises(UserError),
        ):
            order.l10n_co_edi_pos_action_send_document()

        self.assertEqual(order.l10n_co_edi_pos_dian_state, 'invoice_rejected')

    def test_send_bill_sync_duplicated_fallback_date_no_match(self):
        """ Same as test_send_bill_sync_duplicated_fallback_matches (ID, amount and both parties'
        CompanyID all match), but the fetched DIAN document has a different issue date - covers
        e.g. two different orders from the same anonymous "Consumidor Final" customer, for the
        same amount, on different days (a coffee/sandwich shop scenario where CompanyID alone
        doesn't discriminate between orders since walk-in customers share one generic ID).
        """
        order = self.test_send_bill_sync_errors()  # 1st attempt: rejected for an unrelated reason

        outgoing_xml, errors = self.env['pos.edi.xml.ubl_dian']._export_pos_order(order)
        self.assertFalse(errors)
        mismatching_dian_xml = self._build_dian_xml(*self._get_dian_signature(outgoing_xml), issue_date='2000-01-01')

        with (
            self.patched_document('_get_xml_by_document_key_for_company', mismatching_dian_xml),
            self._mock_get_status(),
            patch(f'{self.utils_path}._build_and_send_request', return_value=self._mocked_response('SendBillSync_duplicated.xml', 200)),
            self.assertRaises(UserError),
        ):
            order.l10n_co_edi_pos_action_send_document()

        self.assertEqual(order.l10n_co_edi_pos_dian_state, 'invoice_rejected')

    def test_action_retry_send_document_bulk(self):
        """ The bulk retry action (Action menu, e.g. on multiple selected orders) recovers
        eligible orders and leaves orders that no longer need it (e.g. already accepted)
        untouched.
        """
        stuck_order = self.test_send_bill_sync_errors()  # rejected for an unrelated reason
        accepted_order = self._create_and_send_order(
            pos_order_ui_data=self.default_pos_order_ui_data, response_file_name='SendBillSync_warnings.xml')
        self.assertEqual(accepted_order.l10n_co_edi_pos_dian_state, 'invoice_accepted')

        with (
            self.patched_document('_parse_errors', []),
            self._mock_get_status(),
            patch(f'{self.utils_path}._build_and_send_request', return_value=self._mocked_response('SendBillSync_warnings.xml', 200)),
        ):
            action = (stuck_order | accepted_order).l10n_co_edi_pos_action_retry_send_document()

        self.assertFalse(action)
        self.assertEqual(stuck_order.l10n_co_edi_pos_dian_state, 'invoice_accepted')
        self.assertEqual(accepted_order.l10n_co_edi_pos_dian_state, 'invoice_accepted')

    def _create_failed_order(self):
        # NOTE: unlike test_send_bill_sync_errors(), which returns
        # self.config.session_ids.order_ids[0] (always the *first* order across all sessions),
        # this returns the order just created, so callers can create several distinct ones.
        known_orders = self.config.session_ids.order_ids
        try:
            self._create_and_send_order(pos_order_ui_data=self.default_pos_order_ui_data, response_file_name='SendBillSync_errors.xml')
        except UserError:
            pass
        return self.config.session_ids.order_ids - known_orders

    def test_action_retry_send_document_bulk_reports_failures(self):
        """ An order that still fails on retry doesn't roll back another order that succeeded
        in the same batch: failures are reported via a notification instead of raising, and
        logged on the failed order's chatter.
        """
        failed_order = self._create_failed_order()
        recovered_order = self._create_failed_order()

        # keyed by which order is being (re)sent, rather than call order, since the recordset
        # iteration order of `failed_order | recovered_order` isn't guaranteed
        def send_bill_sync(data):
            if data['record'] == recovered_order:
                return {'state': 'invoice_accepted', 'message_json': {'status': "Procesado Correctamente."}}
            return {
                'state': 'invoice_rejected',
                'message_json': {
                    'status': "Documento con errores en campos mandatorios.",
                    'errors': ["Regla: ZB01, Rechazo: Fallo en el esquema XML del archivo"],
                },
            }

        with (
            self._mock_get_status(),
            patch.object(self.registry['l10n_co_edi.document'], '_l10n_co_edi_pos_send_bill_sync', side_effect=send_bill_sync),
        ):
            action = (failed_order | recovered_order).l10n_co_edi_pos_action_retry_send_document()

        self.assertEqual(failed_order.l10n_co_edi_pos_dian_state, 'invoice_rejected')
        self.assertEqual(recovered_order.l10n_co_edi_pos_dian_state, 'invoice_accepted')

        self.assertEqual(action['type'], 'ir.actions.client')
        self.assertEqual(action['params']['type'], 'danger')
        self.assertIn(failed_order.display_name, action['params']['message'])
        self.assertNotIn(recovered_order.display_name, action['params']['message'])
        self.assertIn("Regla: ZB01", failed_order.message_ids[0].body)

    def test_send_bill_sync_second_attempt(self):
        """ First attempt SendBillSync returns errors, second attempt is successful. """
        # 1st attempt (fail)
        order = self.test_send_bill_sync_errors()

        self.assertFalse(order.l10n_co_edi_pos_attachment_id)
        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'zip_key': False,
            'state': 'invoice_rejected',
            'message': Markup(
                "<p>Documento con errores en campos mandatorios.</p>"
                "<ul><li>Regla: ZB01, Rechazo: Fallo en el esquema XML del archivo</li></ul>"
            ),
        }])

        # 2nd attempt (success without errors or warnings)
        with (
            self.patched_document('_parse_errors', []),
            self._mock_get_status(),
            patch(f'{self.utils_path}._build_and_send_request', return_value=self._mocked_response('SendBillSync_warnings.xml', 200)),
        ):
            order.l10n_co_edi_pos_action_send_document()

        self.assertEqual(len(order.l10n_co_edi_pos_document_ids), 1)  # no need to keep the rejected documents
        self.assertTrue(order.l10n_co_edi_pos_attachment_id)
        self.assertRecordValues(order.l10n_co_edi_pos_document_ids, [{
            'zip_key': False,
            'state': 'invoice_accepted',
            'message': Markup("<p>Procesado Correctamente.</p>"),
        }])

    def test_invoiced_pos_order(self):
        self.config.company_id.write({
            'l10n_co_edi_test_environment': True,
            'l10n_co_edi_certification_process': True,
        })

        with (
            self._pos_session(),
            self._mock_get_status(),
            self._disable_get_acquirer_call(),
            patch(f'{self.utils_path}._build_and_send_request', return_value=self._mocked_response('SendTestSetAsync.xml', 200)),
        ):
            order = self._create_order({
                **self.default_pos_order_ui_data,
                'is_invoiced': True,
                'customer': self.partner_co,
            })

            self.assertRecordValues(order, [{
                'to_invoice': True,
                'l10n_co_edi_pos_document_ids': self.env['l10n_co_edi.document'],
            }])
            self.assertTrue(order.account_move)

            move = order.account_move
            self._mock_send_and_print(move=move, response_file='SendTestSetAsync.xml')

            self.assertRecordValues(move.l10n_co_edi_document_ids, [{
                'zip_key': '42424242',
                'state': 'invoice_pending',
                'message': Markup("<p>Invoice is being processed by the DIAN.</p>"),
            }])
            self.assertEqual(move.l10n_co_edi_state, 'invoice_pending')

    def test_session_report(self):
        self.config.company_id.write({
            'l10n_co_edi_test_environment': True,
            'l10n_co_edi_certification_process': True,
        })
        self.config.l10n_co_edi_pos_serial_number = "Test CO SN"

        with (
            self._pos_session(),
            self._mock_get_status(),
            self._disable_get_acquirer_call(),
            patch(f'{self.utils_path}._build_and_send_request', return_value=self._mocked_response('SendTestSetAsync.xml', 200)),
        ):
            order = self._create_order({
                **self.default_pos_order_ui_data,
                'is_invoiced': True,
                'customer': self.partner_co,
            })
        report = self.env['report.point_of_sale.report_saledetails'].get_sale_details(
            config_ids=order.session_id.config_id.ids,
            session_ids=order.session_id.ids
        )
        self.assertIn("Test CO SN", report['l10n_co_edi_pos_serial_number'])
