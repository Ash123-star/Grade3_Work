export type WorkEvent = {event: string; id?: string; data: string};

/** Bearer 留在请求头；解析跨块 UTF-8、CRLF、多行 data 和心跳。 */
export async function readWorkEvents(response: Response, signal: AbortSignal, receive: (event: WorkEvent) => void) {
  if (!response.body || !response.headers.get('content-type')?.includes('text/event-stream')) throw new Error('STREAM_UNAVAILABLE');
  const reader = response.body.getReader(), decoder = new TextDecoder();
  let buffer = '', event = 'message', id: string | undefined, data: string[] = [];
  const line = (value: string) => {
    if (!value) {
      if (data.length && !signal.aborted) receive({event, id, data: data.join('\n')});
      event = 'message'; id = undefined; data = [];
      return;
    }
    if (value.startsWith(':')) return;
    const colon = value.indexOf(':'), field = colon < 0 ? value : value.slice(0, colon);
    let content = colon < 0 ? '' : value.slice(colon + 1);
    if (content.startsWith(' ')) content = content.slice(1);
    if (field === 'event') event = content;
    if (field === 'id' && !content.includes('\0')) id = content;
    if (field === 'data') data.push(content);
  };
  const abort = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', abort, {once: true});
  try {
    while (!signal.aborted) {
      const part = await reader.read();
      if (part.done) break;
      buffer += decoder.decode(part.value, {stream: true});
      if (buffer.length > 65536) throw new Error('STREAM_INVALID');
      let end: number;
      while ((end = buffer.indexOf('\n')) >= 0) {
        line(buffer.slice(0, end).replace(/\r$/, ''));
        buffer = buffer.slice(end + 1);
      }
    }
  } finally {
    signal.removeEventListener('abort', abort);
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

export class WorkEventCursor {
  value = '0';
  accept(event: WorkEvent) {
    if (event.event !== 'change' || !/^[0-9]+$/.test(event.id ?? '')) return false;
    if (BigInt(event.id!) <= BigInt(this.value)) return false;
    this.value = event.id!;
    return true;
  }
}
