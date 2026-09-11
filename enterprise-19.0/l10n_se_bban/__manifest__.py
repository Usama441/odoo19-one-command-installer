# Part of Odoo. See LICENSE file for full copyright and licensing details.

{
    'name': 'BBAN Plusgiro Bankgiro',
    'version': '1.0',
    'category': 'Accounting/Localizations',
    'author': 'XCLUDE',
    'summary': 'Implements BBAN Plusgiro Bankgiro',
    'description': """
        This adds support for BBAN, Plusgiro & Bankgiro for swedish accounts.
        It adapts the XML payment format for ISO20022 payments if the account number
        is a BBAN, Plusgiro or Bankgiro account.
        This module can be installed without installing the Swedish localization enabling
        the use of those accounts for non swedish companies.
    """,
    'depends': ['account_iso20022'],
    'data': [
        'data/se.bban.clear.range.csv',
        'security/ir.model.access.csv',
        'views/se_bban_clear_range.xml',
    ],
    'countries': ['SE'],
    'installable': True,
    'license': 'OEEL-1',
}
