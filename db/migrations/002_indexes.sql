
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);

CREATE INDEX IF NOT EXISTS idx_booking_events_booking_id_created_at
    ON booking_events (booking_id, created_at);
