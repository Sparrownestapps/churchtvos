-- Upload requests can now carry a pending action, so a person can upload AND confirm in one step on the upload page,
-- and an assistant with a shell can upload straight to storage with a one-time signed URL.
--   plan:         schedule_signage arguments (without items) to run once the files are uploaded; null = just upload
--   summary:      the preview text shown on the upload page next to the "Upload & schedule" button
--   result:       what happened (filled in by the upload page after scheduling)
--   storage_path: for signed-URL uploads, where the file will land; check_upload turns it into a media row
alter table public.mcp_upload_requests add column plan jsonb;
alter table public.mcp_upload_requests add column summary text;
alter table public.mcp_upload_requests add column result text;
alter table public.mcp_upload_requests add column storage_path text;
alter table public.mcp_upload_requests add column media_ids uuid[];
