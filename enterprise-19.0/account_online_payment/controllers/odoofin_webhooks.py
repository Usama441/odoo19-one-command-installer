from odoo.http import Controller, request, route


class OdooFinWebhooksController(Controller):

    @route('/webhook/odoofin/payment_activated', type='jsonrpc', auth='public', methods=['POST'])
    def payments_activated(self):
        data = request.get_json_data()
        if link := request.env['account.online.link'].sudo().search([('client_id', '=', data.get('client_id'))], limit=1):
            link.is_payment_activated = True
        return True
