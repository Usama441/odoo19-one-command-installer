import odoo
from odoo.addons.point_of_sale.tests.common import CommonPosTest


@odoo.tests.tagged('post_install', '-at_install')
class TestPosAppointmentFlow(CommonPosTest):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env.user.group_ids += cls.env.ref('appointment.group_appointment_manager')

        cls.reservation_appointment = cls.env['appointment.type'].create({
            'appointment_tz': 'UTC',
            'is_auto_assign': True,
            'min_schedule_hours': 1.0,
            'max_schedule_days': 8,
            'name': 'Test',
            'manage_capacity': True,
            'schedule_based_on': 'resources',
        })
        cls.resource_1, cls.resource_2 = cls.env['appointment.resource'].create([
            {
                'capacity': 4,
                'name': 'Table of 4',
                'appointment_type_ids': cls.reservation_appointment.ids,
            },
            {
                'capacity': 2,
                'name': 'Table of 2',
                'appointment_type_ids': cls.reservation_appointment.ids,
            }
        ])
        cls.env.user.group_ids -= cls.env.ref('appointment.group_appointment_manager')

    def test_appointment_reservation_count(self):
        """ Test that bookings are created with the correct number of reservation. """

        # Reservation should depend on resource_total_capacity_reserved
        capacity_reservation = self.env['calendar.event'].create({
            'name': 'event without partner',
            'resource_ids': self.resource_1.ids,
            'total_capacity_reserved': 3,
            'appointment_type_id': self.reservation_appointment.id,
        })
        self.assertEqual(capacity_reservation.waiting_list_capacity, 3)

        # resource_total_capacity_reserved has priority over resource_ids
        capacity_reservation_2 = self.env['calendar.event'].create({
            'name': 'event without partner',
            'total_capacity_reserved': 5,
            'appointment_type_id': self.reservation_appointment.id,
            'resource_ids': [(4, self.resource_1.id), (4, self.resource_2.id)],
        })
        self.assertEqual(capacity_reservation_2.waiting_list_capacity, 5)

        # Reservation should depend on resource_ids
        resource_reservation = self.env['calendar.event'].create({
            'name': 'event without partner',
            'appointment_type_id': self.reservation_appointment.id,
            'resource_ids': [(4, self.resource_1.id), (4, self.resource_2.id)],
        })
        self.assertEqual(resource_reservation.waiting_list_capacity, 6)
