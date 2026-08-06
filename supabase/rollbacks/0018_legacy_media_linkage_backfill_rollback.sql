-- Rollback for: 0018_legacy_media_linkage_backfill
--
-- Deletes exactly the 7 rows this migration adds, identified by their
-- precise (revision_id, storage_path) pairs — not a broader pattern
-- match, so it can't accidentally remove a legitimate row added by
-- something else later. Only use this if 0018 itself needs to be undone;
-- there is no reason to prefer the original (unlinked) behavior
-- otherwise — it just makes these 7 revision images unreadable again,
-- falling back to the Migration B compatibility layer's graceful
-- placeholder.

begin;

delete from public.revision_media
where (revision_id, storage_path) in (
    ('070cc44b-c7fe-4070-bf68-1cb4ce64f4af', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540195367-Screenshot 2026-01-25 203600.png'),
    ('31cdd3f9-fcd2-4509-8d58-f0ed361960f5', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540440054-Screenshot 2026-01-25 203600.png'),
    ('21f12b41-ae58-40e9-b9e6-59c85200369a', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540456590-Screenshot 2026-01-25 203600.png'),
    ('a0c03e2a-57cf-4ce8-9090-cff421a22626', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540460231-Screenshot 2026-01-25 203600.png'),
    ('f70b904c-84c7-42cc-af08-6729cf228d09', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/revisions/1783540741159-Screenshot 2026-01-25 203600.png'),
    ('f59e6c5b-a71a-4828-9cd5-37f0d73067a5', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/1783986632675-screenshot-2026-06-15-124317.png'),
    ('7f5be50a-f7b4-4f67-b34c-499bd3b5b822', 'dacdf29e-ea56-4a85-a6a3-6a60cb7c1210/updates/1784082807634-screenshot-2026-06-15-124311.png')
);

commit;
