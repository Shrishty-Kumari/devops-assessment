INSERT INTO hotel_bookings (
    id,
    org_id,
    hotel_id,
    city,
    checkin_date,
    checkout_date,
    amount,
    status,
    created_at
)
SELECT
    gen_random_uuid(),

    (ARRAY[
        '11111111-1111-1111-1111-111111111111'::uuid,
        '22222222-2222-2222-2222-222222222222'::uuid,
        '33333333-3333-3333-3333-333333333333'::uuid,
        '44444444-4444-4444-4444-444444444444'::uuid,
        '55555555-5555-5555-5555-555555555555'::uuid
    ])[1 + (g % 5)],

    'HOTEL-' || LPAD((1 + (g % 500))::text, 4, '0'),

    (ARRAY[
        'delhi',
        'mumbai',
        'bangalore',
        'hyderabad',
        'chennai',
        'kolkata',
        'pune',
        'jaipur',
        'chandigarh',
        'goa'
    ])[1 + (g % 10)],

    (NOW() - (((g * 7919) % 365) || ' days')::interval)::date + (1 + (g % 45)),
    (NOW() - (((g * 7919) % 365) || ' days')::interval)::date + (1 + (g % 45)) + (1 + (g % 6)),

    (1500 + ((g * 977) % 48500))::numeric(12, 2),

    (ARRAY[
        'confirmed',
        'cancelled',
        'pending',
        'completed'
    ])[1 + ((g * 3) % 4)],

    NOW()
    - (((g * 7919) % 365) || ' days')::interval
    - (((g * 37) % 24) || ' hours')::interval

FROM generate_series(1, 100000) AS g
WHERE NOT EXISTS (SELECT 1 FROM hotel_bookings);


WITH sampled AS (
    SELECT
        id,
        hotel_id,
        amount,
        status,
        created_at,
        ROW_NUMBER() OVER (ORDER BY created_at, id) AS rn
    FROM hotel_bookings
)
INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
    s.id,
    e.event_type,
    jsonb_build_object(
        'source', 'seed',
        'channel', CASE WHEN (s.rn % 2) = 0 THEN 'web' ELSE 'mobile_app' END,
        'hotel_id', s.hotel_id,
        'amount', s.amount,
        'booking_status', s.status
    ),
    s.created_at + (e.offset_minutes || ' minutes')::interval
FROM sampled AS s
CROSS JOIN LATERAL (
    VALUES
        ('booking_created', 0),
        ('payment_captured', 12),
        ('booking_confirmed', 30)
) AS e (event_type, offset_minutes)
WHERE s.rn % 10 = 0
  AND NOT EXISTS (SELECT 1 FROM booking_events);


WITH sampled AS (
    SELECT
        id,
        amount,
        created_at,
        ROW_NUMBER() OVER (ORDER BY created_at, id) AS rn
    FROM hotel_bookings
    WHERE status = 'cancelled'
)
INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
    s.id,
    'refund_issued',
    jsonb_build_object(
        'source', 'seed',
        'refund_amount', s.amount,
        'reason', 'guest_cancelled'
    ),
    s.created_at + interval '2 days'
FROM sampled AS s
WHERE s.rn % 10 = 0
  AND NOT EXISTS (
      SELECT 1 FROM booking_events WHERE event_type = 'refund_issued'
  );

VACUUM ANALYZE hotel_bookings;
VACUUM ANALYZE booking_events;
