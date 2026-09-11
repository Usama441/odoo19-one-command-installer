from odoo import api, fields, models

from odoo.addons.voip.models.utils import extract_country_code


class VoipCountryCode(models.AbstractModel):
    """Mixin to compute the ISO country code from a phone number.

    This mixin extracts the country ISO code (e.g. "be" for Belgium) from the
    international dialing prefix of the phone number (e.g. "+32"). This is
    useful for displaying country flags or identifying the origin of a phone
    number.

    Models inheriting this mixin should have a phone number field. If the field
    is not named 'phone', they should override `_voip_get_phone_field()`.
    """

    _name = "voip.country.code.mixin"
    _description = "Country Code Mixin"

    country_code_from_phone = fields.Char(
        compute="_compute_country_code_from_phone",
        export_string_translation=False,
        help=(
            "Computes the country ISO code (e.g. be for Belgium) from the phone number dialing code (e.g. +32), if any.\n"
            "Useful for displaying the flag associated with a phone number."
        ),
    )

    @api.depends(lambda self: self._phone_get_number_fields())
    def _compute_country_code_from_phone(self) -> None:
        fields = self._phone_get_number_fields()
        sanitized_fields = [f"{field}_sanitized" for field in fields if "sanitized" not in field]
        sanitized_fields = [field for field in sanitized_fields if field in self]
        for record in self:
            for field in [*sanitized_fields, *fields]:
                phone_number = record[field]
                if not phone_number:
                    continue
                iso_code = extract_country_code(phone_number)["iso"]
                if not iso_code:
                    continue
                record.country_code_from_phone = iso_code
                break
            else:
                record.country_code_from_phone = ""
