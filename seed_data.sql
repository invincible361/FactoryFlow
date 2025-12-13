-- Seed Workers
INSERT INTO workers (worker_id, name, username, password)
VALUES 
('W-001', 'Worker 1', 'worker1', 'password1'),
('W-002', 'Worker 2', 'worker2', 'password2'),
('W-003', 'Worker 3', 'worker3', 'password3'),
('W-004', 'Worker 4', 'worker4', 'password4'),
('W-005', 'Worker 5', 'worker5', 'password5')
ON CONFLICT (username) DO NOTHING;

-- Seed Items (with JSONB for operation_details)
INSERT INTO items (item_id, name, operations, operation_details)
VALUES 
('RET-001', 'Retailer', ARRAY['Operation 1', 'Operation 2', 'Operation 3'], 
  '[{"name": "Operation 1", "target": 100}, {"name": "Operation 2", "target": 100}, {"name": "Operation 3", "target": 100}]'::jsonb),

('SP-001', 'Seat Pipe', ARRAY['Operation 1', 'Operation 2'], 
  '[{"name": "Operation 1", "target": 50}, {"name": "Operation 2", "target": 50}]'::jsonb),

('GR-122', 'Gear 122', ARRAY['CNC Op 1', 'CNC Op 2', 'CNC Op 3', 'CNC Op 4', 'VMC Op 1', 'VMC Op 2'], 
  '[
    {"name": "CNC Op 1", "target": 60}, 
    {"name": "CNC Op 2", "target": 60},
    {"name": "CNC Op 3", "target": 60},
    {"name": "CNC Op 4", "target": 60},
    {"name": "VMC Op 1", "target": 40},
    {"name": "VMC Op 2", "target": 40}
   ]'::jsonb)
ON CONFLICT (item_id) DO NOTHING;

-- Seed Machines
INSERT INTO machines (machine_id, name, type)
VALUES 
('CNC-1', 'CNC Machine 1', 'CNC'),
('CNC-2', 'CNC Machine 2', 'CNC'),
('CNC-3', 'CNC Machine 3', 'CNC'),
('CNC-4', 'CNC Machine 4', 'CNC'),
('CNC-5', 'CNC Machine 5', 'CNC'),
('VMC-1', 'VMC Machine 1', 'VMC'),
('VMC-2', 'VMC Machine 2', 'VMC')
ON CONFLICT (machine_id) DO NOTHING;
