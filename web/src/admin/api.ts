export interface Page<T> { items: T[]; total: number; nextCursor: string }
export interface Option { id: string; name: string; department_id?: string }
export interface Account { id: string; account: string; name: string; phone: string; role: string; status: string; department_id: string | null; team_id: string | null; manager_id: string | null; department: string | null; team: string | null; version: number; dispatch_enabled: boolean; company_reviewer: boolean; pendingReviews?: { id: string; kind: string }[] }
export interface CompanyItem { id?: string; title: string; text: string; pinned: boolean; archived: boolean; position: number; version: number }
export interface Review { id: string; kind: string; target_id: string; status: string; reason: string; expected_version?: number; applicant_id: string; applicant_name?: string; created_at: string; candidate?: Record<string, unknown>; before_value?: Record<string, unknown>; steps?: { reviewer_id: string; state: string; position: number; reason?: string }[] }
export const roles: Record<string, string> = { ADMIN: '管理员', FOUNDER: '创始人', DIRECTOR: '部门负责人', LEADER: '团队长', EMPLOYEE: '员工' };
export const statuses: Record<string, string> = { ACTIVE: '已启用', PENDING: '待确认', DISABLED: '已停用', APPROVED: '已通过', REJECTED: '已驳回' };
export class ApiError extends Error { constructor(message: string, public status: number, public code: string) { super(message); } }
const requests = new Set<AbortController>();
let generation = 0;
export function cancelRequests() { generation++; for (const controller of requests) controller.abort(); requests.clear(); }
export function errorMessage(error: unknown) { return error instanceof Error ? error.message : '请求失败，请稍后重试'; }
export async function api<T>(path: string, options: { method?: string; body?: unknown; query?: Record<string, string | number> } = {}): Promise<T> {
  const controller = new AbortController(), ticket = generation;
  requests.add(controller);
  const auth = path.startsWith('/auth/');
  const endpoint = auth ? `/api${path}` : `/api/admin/workspace/management${path}`;
  const query = options.query ? '?' + new URLSearchParams(Object.entries(options.query).map(([key, value]) => [key, String(value)])) : '';
  try {
    const token = sessionStorage.getItem('workpanel-token');
    const response = await fetch(endpoint + query, { method: options.method ?? 'GET', signal: controller.signal, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(options.body !== undefined ? { 'Content-Type': 'application/json' } : {}) }, body: options.body === undefined ? undefined : JSON.stringify(options.body) });
    const data = await response.json().catch(() => ({ message: `服务暂不可用（${response.status}）` }));
    if (ticket !== generation) throw new DOMException('请求已取消', 'AbortError');
    if (!response.ok) {
      const trace = data.traceId ?? response.headers.get('X-Trace-Id');
      const message = `${data.message ?? '请求失败'}${trace ? `（追踪号：${trace}）` : ''}`;
      if ((response.status === 401 && !path.endsWith('/login')) || (response.status === 403 && !path.includes('/reviews/'))) window.dispatchEvent(new CustomEvent('management-access-lost', { detail: message }));
      throw new ApiError(message, response.status, data.code ?? 'REQUEST_FAILED');
    }
    return data as T;
  } finally { requests.delete(controller); }
}
