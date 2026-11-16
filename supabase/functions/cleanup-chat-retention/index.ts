import { createClient } from 'npm:@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL');
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const cronSecret = Deno.env.get('CHAT_RETENTION_CRON_SECRET');
if (!supabaseUrl || !serviceRoleKey || !cronSecret) {
  throw new Error('Chat retention function environment is not configured.');
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const batchSize = 500;
const maxBatchesPerRun = 20;
const privateMediaBucket = 'chat-media';
const messageTables = ['messages', 'direct_messages'] as const;

type MessageTable = typeof messageTables[number];
type ExpiredMediaRow = {
  id: string;
  media_path: string;
  content: string;
};

function monthsAgo(date: Date, months: number) {
  const result = new Date(date);
  const dayOfMonth = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() - months);
  const lastDayOfMonth = new Date(Date.UTC(
    result.getUTCFullYear(),
    result.getUTCMonth() + 1,
    0,
  )).getUTCDate();
  result.setUTCDate(Math.min(dayOfMonth, lastDayOfMonth));
  return result;
}

async function removeExpiredMedia(table: MessageTable, cutoff: string) {
  let removed = 0;

  for (let batch = 0; batch < maxBatchesPerRun; batch++) {
    const { data, error } = await supabase
      .from(table)
      .select('id, media_path, content')
      .lt('created_at', cutoff)
      .not('media_path', 'is', null)
      .order('created_at')
      .limit(batchSize);

    if (error) throw error;
    const rows = (data ?? []) as ExpiredMediaRow[];
    if (rows.length === 0) break;

    const paths = [...new Set(rows.map((row) => row.media_path))];
    const { error: storageError } = await supabase.storage
      .from(privateMediaBucket)
      .remove(paths);
    if (storageError) throw storageError;

    const emptyMessageIds = rows
      .filter((row) => row.content.trim().length === 0)
      .map((row) => row.id);
    const captionedMessageIds = rows
      .filter((row) => row.content.trim().length > 0)
      .map((row) => row.id);

    if (captionedMessageIds.length > 0) {
      const { error: updateError } = await supabase
        .from(table)
        .update({
          media_path: null,
          media_type: null,
          media_name: null,
        })
        .in('id', captionedMessageIds);
      if (updateError) throw updateError;
    }

    if (emptyMessageIds.length > 0) {
      const { error: deleteError } = await supabase
        .from(table)
        .delete()
        .in('id', emptyMessageIds);
      if (deleteError) throw deleteError;
    }

    removed += paths.length;
    if (rows.length < batchSize) break;
  }

  return removed;
}

async function removeExpiredText(table: MessageTable, cutoff: string) {
  let removed = 0;

  for (let batch = 0; batch < maxBatchesPerRun; batch++) {
    const { data, error } = await supabase
      .from(table)
      .select('id')
      .lt('created_at', cutoff)
      .is('media_path', null)
      .order('created_at')
      .limit(batchSize);

    if (error) throw error;
    const ids = (data ?? []).map((row) => row.id as string);
    if (ids.length === 0) break;

    const { error: deleteError } = await supabase
      .from(table)
      .delete()
      .in('id', ids);
    if (deleteError) throw deleteError;

    removed += ids.length;
    if (ids.length < batchSize) break;
  }

  return removed;
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'Method not allowed' }, { status: 405 });
  }
  if (request.headers.get('x-cron-secret') !== cronSecret) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const now = new Date();
    const mediaCutoff = monthsAgo(now, 3);
    const textCutoff = monthsAgo(now, 6);

    const summary = {
      mediaObjectsRemoved: 0,
      textMessagesRemoved: 0,
    };

    for (const table of messageTables) {
      summary.mediaObjectsRemoved += await removeExpiredMedia(
        table,
        mediaCutoff.toISOString(),
      );
    }
    for (const table of messageTables) {
      summary.textMessagesRemoved += await removeExpiredText(
        table,
        textCutoff.toISOString(),
      );
    }

    return Response.json({ ...summary, completedAt: now.toISOString() });
  } catch (error) {
    console.error('Chat retention cleanup failed:', error);
    return Response.json(
      { error: 'Chat retention cleanup failed.' },
      { status: 500 },
    );
  }
});
