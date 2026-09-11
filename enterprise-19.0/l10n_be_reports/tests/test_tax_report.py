# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo import Command, fields
from odoo.addons.account_reports.tests.account_sales_report_common import AccountSalesReportCommon
from odoo.tests import tagged
from freezegun import freeze_time
from unittest.mock import patch


@tagged('post_install_l10n', 'post_install', '-at_install')
class BelgiumTaxReportTest(AccountSalesReportCommon):

    @classmethod
    @AccountSalesReportCommon.setup_country('be')
    def setUpClass(cls):
        super().setUpClass()
        cls.company.update({
            'vat': 'BE0477472701',
        })

    @freeze_time('2019-12-31')
    def test_generate_xml_minimal(self):
        company = self.env.company
        report = self.env.ref('l10n_be.tax_report_vat')
        options = report.get_options({})

        # The partner id is changing between execution of the test so we need to append it manually to the reference.
        ref = str(company.partner_id.id) + '112019'

        # This is the minimum expected from the belgian tax report xml.
        # As no values are in the report, we only find the grid 71 which is always expected to be present.
        expected_xml = """
        <ns2:VATConsignment xmlns="http://www.minfin.fgov.be/InputCommon" xmlns:ns2="http://www.minfin.fgov.be/VATConsignment" VATDeclarationsNbr="1">
            <ns2:VATDeclaration SequenceNumber="1" DeclarantReference="%s">
                <ns2:Declarant>
                    <VATNumber xmlns="http://www.minfin.fgov.be/InputCommon">0477472701</VATNumber>
                    <Name>company_1_data</Name>
                    <Street></Street>
                    <PostCode></PostCode>
                    <City></City>
                    <CountryCode>BE</CountryCode>
                    <EmailAddress>jsmith@mail.com</EmailAddress>
                    <Phone>+32475123456</Phone>
                </ns2:Declarant>
                <ns2:Period>
                    <ns2:Month>11</ns2:Month>
                    <ns2:Year>2019</ns2:Year>
                </ns2:Period>
                <ns2:Data>
                    <ns2:Amount GridNumber="71">0.00</ns2:Amount>
                </ns2:Data>
                <ns2:ClientListingNihil>NO</ns2:ClientListingNihil>
                <ns2:Ask Restitution="NO"/>
                <ns2:Comment>/</ns2:Comment>
            </ns2:VATDeclaration>
        </ns2:VATConsignment>
        """ % ref

        self.assertXmlTreeEqual(
            self.get_xml_tree_from_string(self.env[report.custom_handler_model_name].export_tax_report_to_xml(options)['file_content']),
            self.get_xml_tree_from_string(expected_xml)
        )

    @freeze_time('2019-12-31')
    def test_generate_xml_minimal_with_comment(self):
        company = self.env.company
        report = self.env.ref('l10n_be.tax_report_vat')
        options = report.get_options({})
        options['comment'] = "foo"

        ref = str(company.partner_id.id) + '112019'

        # This is the minimum expected from the belgian tax report xml.
        # As no values are in the report, we only find the grid 71 which is always expected to be present.
        expected_xml = """
               <ns2:VATConsignment xmlns="http://www.minfin.fgov.be/InputCommon" xmlns:ns2="http://www.minfin.fgov.be/VATConsignment" VATDeclarationsNbr="1">
                   <ns2:VATDeclaration SequenceNumber="1" DeclarantReference="%s">
                       <ns2:Declarant>
                           <VATNumber xmlns="http://www.minfin.fgov.be/InputCommon">0477472701</VATNumber>
                           <Name>company_1_data</Name>
                           <Street></Street>
                           <PostCode></PostCode>
                           <City></City>
                           <CountryCode>BE</CountryCode>
                           <EmailAddress>jsmith@mail.com</EmailAddress>
                           <Phone>+32475123456</Phone>
                       </ns2:Declarant>
                       <ns2:Period>
                           <ns2:Month>11</ns2:Month>
                           <ns2:Year>2019</ns2:Year>
                       </ns2:Period>
                       <ns2:Data>
                           <ns2:Amount GridNumber="71">0.00</ns2:Amount>
                       </ns2:Data>
                       <ns2:ClientListingNihil>NO</ns2:ClientListingNihil>
                       <ns2:Ask Restitution="NO"/>
                       <ns2:Comment>foo</ns2:Comment>
                   </ns2:VATDeclaration>
               </ns2:VATConsignment>
               """ % ref

        self.assertXmlTreeEqual(
            self.get_xml_tree_from_string(
                self.env[report.custom_handler_model_name].export_tax_report_to_xml(options)['file_content']),
            self.get_xml_tree_from_string(expected_xml)
        )

    @freeze_time('2019-12-31')
    def test_generate_xml_minimal_with_representative(self):
        company = self.env.company
        report = self.env.ref('l10n_be.tax_report_vat')
        options = report.get_options({})

        # Create a new partner for the representative and link it to the company.
        representative = self.env['res.partner'].create({
            'company_type': 'company',
            'name': 'Fidu BE',
            'street': 'Fidu Street 123',
            'city': 'Brussels',
            'zip': '1000',
            'country_id': self.env.ref('base.be').id,
            'vat': 'BE0477472701',
            'phone': '+32470123456',
            'email': 'info@fidu.be',
        })
        company.account_representative_id = representative.id

        # The partner_id is changing between execution of the test so we need to append it manually to the reference.
        ref = str(company.partner_id.id) + '112019'

        # This is the minimum expected from the belgian tax report XML.
        # Only the representative node has been added to make sure it appears in the XML.
        expected_xml = """
            <ns2:VATConsignment xmlns="http://www.minfin.fgov.be/InputCommon" xmlns:ns2="http://www.minfin.fgov.be/VATConsignment" VATDeclarationsNbr="1">
                <ns2:Representative>
                    <RepresentativeID identificationType="NVAT" issuedBy="BE">0477472701</RepresentativeID>
                    <Name>Fidu BE</Name>
                    <Street>Fidu Street 123</Street>
                    <PostCode>1000</PostCode>
                    <City>Brussels</City>
                    <CountryCode>BE</CountryCode>
                    <EmailAddress>info@fidu.be</EmailAddress>
                    <Phone>+32470123456</Phone>
                </ns2:Representative>
                <ns2:VATDeclaration SequenceNumber="1" DeclarantReference="%s">
                    <ns2:Declarant>
                        <VATNumber xmlns="http://www.minfin.fgov.be/InputCommon">0477472701</VATNumber>
                        <Name>company_1_data</Name>
                        <Street></Street>
                        <PostCode></PostCode>
                        <City></City>
                        <CountryCode>BE</CountryCode>
                        <EmailAddress>jsmith@mail.com</EmailAddress>
                        <Phone>+32475123456</Phone>
                    </ns2:Declarant>
                    <ns2:Period>
                        <ns2:Month>11</ns2:Month>
                        <ns2:Year>2019</ns2:Year>
                    </ns2:Period>
                    <ns2:Data>
                        <ns2:Amount GridNumber="71">0.00</ns2:Amount>
                    </ns2:Data>
                    <ns2:ClientListingNihil>NO</ns2:ClientListingNihil>
                    <ns2:Ask Restitution="NO"/>
                    <ns2:Comment>/</ns2:Comment>
                </ns2:VATDeclaration>
            </ns2:VATConsignment>
            """ % ref

        self.assertXmlTreeEqual(
            self.get_xml_tree_from_string(self.env[report.custom_handler_model_name].export_tax_report_to_xml(options)['file_content']),
            self.get_xml_tree_from_string(expected_xml)
        )

    @freeze_time('2019-12-31')
    def test_generate_xml(self):
        company = self.env.company
        first_tax = self.env['account.tax'].search([('name', '=', '21% M'), ('company_id', '=', self.company_data['company'].id)], limit=1)
        second_tax = self.env['account.tax'].search([('name', '=', '21% M.Cocont'), ('company_id', '=', self.company_data['company'].id)], limit=1)

        # Create and post a move with two move lines to get some data in the report
        move = self.env['account.move'].create({
            'move_type': 'in_invoice',
            'journal_id': self.company_data['default_journal_purchase'].id,
            'partner_id': self.partner_a.id,
            'invoice_date': '2019-11-12',
            'date': '2019-11-12',
            'invoice_line_ids': [(0, 0, {
                'product_id': self.product_a.id,
                'quantity': 1.0,
                'name': 'product test 1',
                'price_unit': 100,
                'tax_ids': first_tax.ids,
            }), (0, 0, {
                'product_id': self.product_b.id,
                'quantity': 1.0,
                'name': 'product test 2',
                'price_unit': 50,
                'tax_ids': second_tax.ids,
            })]
        })
        move.action_post()

        report = self.env.ref('l10n_be.tax_report_vat')
        options = report.get_options({})

        # The partner id is changing between execution of the test so we need to append it manually to the reference.
        ref = str(company.partner_id.id) + '112019'

        expected_xml = """
        <ns2:VATConsignment xmlns="http://www.minfin.fgov.be/InputCommon" xmlns:ns2="http://www.minfin.fgov.be/VATConsignment" VATDeclarationsNbr="1">

            <ns2:VATDeclaration SequenceNumber="1" DeclarantReference="%s">
                <ns2:Declarant>
                    <VATNumber xmlns="http://www.minfin.fgov.be/InputCommon">0477472701</VATNumber>
                    <Name>company_1_data</Name>
                    <Street></Street>
                    <PostCode></PostCode>
                    <City></City>
                    <CountryCode>BE</CountryCode>
                    <EmailAddress>jsmith@mail.com</EmailAddress>
                    <Phone>+32475123456</Phone>
                </ns2:Declarant>
                <ns2:Period>
                    <ns2:Month>11</ns2:Month>
                    <ns2:Year>2019</ns2:Year>
                </ns2:Period>
                <ns2:Data>
                    <ns2:Amount GridNumber="56">10.50</ns2:Amount>
                    <ns2:Amount GridNumber="59">31.50</ns2:Amount>
                    <ns2:Amount GridNumber="72">21.00</ns2:Amount>
                    <ns2:Amount GridNumber="81">150.00</ns2:Amount>
                    <ns2:Amount GridNumber="87">50.00</ns2:Amount>
                </ns2:Data>
                <ns2:ClientListingNihil>NO</ns2:ClientListingNihil>
                <ns2:Ask Restitution="NO"/>
                <ns2:Comment>/</ns2:Comment>
            </ns2:VATDeclaration>
        </ns2:VATConsignment>
        """ % ref

        self.assertXmlTreeEqual(
            self.get_xml_tree_from_string(self.env['l10n_be.tax.report.handler'].export_tax_report_to_xml(options)['file_content']),
            self.get_xml_tree_from_string(expected_xml)
        )

    @freeze_time('2019-12-31')
    def test_generate_xml_vat_unit(self):
        company = self.env.company
        company_2 = self.company_data_2['company']
        unit_companies = company + company_2

        company_2.currency_id = company.currency_id

        tax_unit = self.env['account.tax.unit'].create({
            'name': "One unit to rule them all",
            'country_id': company.country_id.id,
            'vat': "BE0477472701",
            'company_ids': [Command.set(unit_companies.ids)],
            'main_company_id': company.id,
        })

        first_tax = self.env['account.tax'].search([('name', '=', '21% M'), ('company_id', '=', self.company_data['company'].id)], limit=1)
        second_tax = self.env['account.tax'].search([('name', '=', '21% M.Cocont'), ('company_id', '=', self.company_data['company'].id)], limit=1)

        # Create and post a move with two move lines to get some data in the report
        move = self.env['account.move'].create({
            'move_type': 'in_invoice',
            'journal_id': self.company_data['default_journal_purchase'].id,
            'partner_id': self.partner_a.id,
            'invoice_date': '2019-11-12',
            'date': '2019-11-12',
            'invoice_line_ids': [(0, 0, {
                'product_id': self.product_a.id,
                'quantity': 1.0,
                'name': 'product test 1',
                'price_unit': 100,
                'tax_ids': first_tax.ids,
            }), (0, 0, {
                'product_id': self.product_b.id,
                'quantity': 1.0,
                'name': 'product test 2',
                'price_unit': 50,
                'tax_ids': second_tax.ids,
            })]
        })
        move.action_post()

        report = self.env.ref('l10n_be.tax_report_vat')
        options = report.get_options({})
        options['tax_unit'] = tax_unit.id

        # The partner id is changing between execution of the test so we need to append it manually to the reference.
        ref = str(company.partner_id.id) + '112019'

        expected_xml = """
        <ns2:VATConsignment xmlns="http://www.minfin.fgov.be/InputCommon" xmlns:ns2="http://www.minfin.fgov.be/VATConsignment" VATDeclarationsNbr="1">

            <ns2:VATDeclaration SequenceNumber="1" DeclarantReference="%s">
                <ns2:Declarant>
                    <VATNumber xmlns="http://www.minfin.fgov.be/InputCommon">0477472701</VATNumber>
                    <Name>company_1_data</Name>
                    <Street></Street>
                    <PostCode></PostCode>
                    <City></City>
                    <CountryCode>BE</CountryCode>
                    <EmailAddress>jsmith@mail.com</EmailAddress>
                    <Phone>+32475123456</Phone>
                </ns2:Declarant>
                <ns2:Period>
                    <ns2:Month>11</ns2:Month>
                    <ns2:Year>2019</ns2:Year>
                </ns2:Period>
                <ns2:Data>
                    <ns2:Amount GridNumber="00">0.00</ns2:Amount>
                    <ns2:Amount GridNumber="56">10.50</ns2:Amount>
                    <ns2:Amount GridNumber="59">31.50</ns2:Amount>
                    <ns2:Amount GridNumber="72">21.00</ns2:Amount>
                    <ns2:Amount GridNumber="81">150.00</ns2:Amount>
                    <ns2:Amount GridNumber="87">50.00</ns2:Amount>
                </ns2:Data>
                <ns2:ClientListingNihil>NO</ns2:ClientListingNihil>
                <ns2:Ask Restitution="NO"/>
                <ns2:Comment>/</ns2:Comment>
            </ns2:VATDeclaration>
        </ns2:VATConsignment>
        """ % ref
        self.assertXmlTreeEqual(
            self.get_xml_tree_from_string(self.env[report.custom_handler_model_name].export_tax_report_to_xml(options)['file_content']),
            self.get_xml_tree_from_string(expected_xml)
        )

    @freeze_time('2019-04-15')
    def test_generate_xml_with_prorata(self):
        company = self.env.company
        account_return = self.env['account.return'].create({
            'name': 'BE Tax Return',
            'type_id': self.env.ref('l10n_be_reports.be_vat_return_type').id,
            'company_id': company.id,
            'date_from': '2019-03-01',
            'date_to': '2019-03-31',
        })

        wizard_lock = self.env['l10n_be_reports.vat.return.lock.wizard'].create({
            'return_id': account_return.id,
            'is_prorata_necessary': True,
            'prorata_year': 2019,
            'prorata': 25,
            'prorata_at_100': 50,
            'prorata_at_0': 50,
        })
        with self.allow_pdf_render():
            wizard_lock.action_proceed_with_locking()
        xml_file = account_return.attachment_ids.filtered(lambda a: a.name.endswith(".xml"))

        # The partner id is changing between execution of the test so we need to append it manually to the reference.
        # Declaring March month, so 3
        ref = str(company.partner_id.id) + '032019'

        # This is the minimum expected from the belgian tax report xml.
        # As no values are in the report, we only find the grid 71 which is always expected to be present.
        expected_xml = """
        <ns2:VATConsignment xmlns="http://www.minfin.fgov.be/InputCommon" xmlns:ns2="http://www.minfin.fgov.be/VATConsignment" VATDeclarationsNbr="1">
            <ns2:VATDeclaration SequenceNumber="1" DeclarantReference="%s">
                <ns2:Declarant>
                    <VATNumber xmlns="http://www.minfin.fgov.be/InputCommon">0477472701</VATNumber>
                    <Name>company_1_data</Name>
                    <Street></Street>
                    <PostCode></PostCode>
                    <City></City>
                    <CountryCode>BE</CountryCode>
                    <EmailAddress>jsmith@mail.com</EmailAddress>
                    <Phone>+32475123456</Phone>
                </ns2:Declarant>
                <ns2:Period>
                    <ns2:Month>03</ns2:Month>
                    <ns2:Year>2019</ns2:Year>
                </ns2:Period>
                <ns2:Deduction>
                    <AdjustedPeriod>2019</AdjustedPeriod>
                    <AdjustedValue>25.00</AdjustedValue>
                    <SpecialAdjustedValue>
                        <moreSpecialProrata>false</moreSpecialProrata>
                        <UseProRataPercentage GridNumber="1">50.00</UseProRataPercentage>
                        <UseProRataPercentage GridNumber="2">50.00</UseProRataPercentage>
                        <UseProRataPercentage GridNumber="3">0.00</UseProRataPercentage>
                    </SpecialAdjustedValue>
                </ns2:Deduction>
                <ns2:Data>
                    <ns2:Amount GridNumber="71">0.00</ns2:Amount>
                </ns2:Data>
                <ns2:ClientListingNihil>YES</ns2:ClientListingNihil>
                <ns2:Ask Restitution="NO"/>
                <ns2:Comment>/</ns2:Comment>
            </ns2:VATDeclaration>
        </ns2:VATConsignment>
        """ % ref

        self.assertXmlTreeEqual(
            self.get_xml_tree_from_attachment(xml_file),
            self.get_xml_tree_from_string(expected_xml)
        )
