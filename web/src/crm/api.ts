import { InvalidContract, pageSize, parseCustomer, parsePage, parseRecord, type CustomerType, type Kind } from './contract';

export const tokenKey = 'workpanel-crm-token';
export class RequestError extends Error {
  constructor(readonly status: number) { super(`Request failed (${status})`); }
}
async function request(path: string, token: string | null, signal?: AbortSignal, body?: unknown): Promise<unknown> {
  const response = await fetch(`/api${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    cache: 'no-store', signal,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!response.ok) throw new RequestError(response.status);
  if (response.status === 204) return null;
  try { return await response.json(); } catch (e) { if (signal?.aborted) throw e; throw new InvalidContract(); }
}
function sessionUser(value: unknown) {
  const user = value as { id?: unknown; name?: unknown; status?: unknown; must_change_password?: unknown } | null;
  if (!user || typeof user.id !== 'string' || typeof user.name !== 'string' || typeof user.status !== 'string' || typeof user.must_change_password !== 'boolean') throw new InvalidContract();
  return { id: user.id, name: user.name, status: user.status, mustChange: user.must_change_password };
}
export async function currentUser(token: string, signal: AbortSignal) { return sessionUser(await request('/auth/me', token, signal)); }
export async function login(account: string, password: string, signal: AbortSignal) {
  const result = await request('/auth/login', null, signal, { account, password }) as { token?: unknown; user?: unknown } | null;
  if (!result || typeof result.token !== 'string' || !result.token) throw new InvalidContract();
  return { token: result.token, user: sessionUser(result.user) };
}
export async function logout(token: string, signal?: AbortSignal) { await request('/auth/logout', token, signal, {}); }
export async function customers(token: string, filters: { search: string; type?: CustomerType; cursor?: string }, signal: AbortSignal) {
  const params = new URLSearchParams({ limit: String(pageSize) });
  if (filters.search) params.set('search', filters.search);
  if (filters.type) params.set('type', filters.type);
  if (filters.cursor) params.set('cursor', filters.cursor);
  return parsePage(await request(`/crm/customers?${params}`, token, signal));
}
export async function customer(token: string, id: string, signal: AbortSignal) {
  return parseCustomer(await request(`/crm/customers/${encodeURIComponent(id)}`, token, signal), id);
}
export async function relatedRecord(token: string, customerId: string, kind: Kind, id: string, signal: AbortSignal) {
  return parseRecord(await request(`/crm/customers/${encodeURIComponent(customerId)}/records/${kind}/${encodeURIComponent(id)}`, token, signal), customerId, kind, id);
}
