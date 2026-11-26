export const orderStatuses = {
  PENDING_PAYMENT: '待支付',
  PAID: '已支付',
  COMPLETED: '已完成',
  CANCELLED: '已取消',
  REFUNDED: '已退款',
  PARTIALLY_REFUNDED: '部分退款',
};
export const memberStatuses = { ACTIVE: '有效', EXPIRED: '已到期', DISABLED: '已停用' };

export interface Counts { applied: number; unchanged: number; stale: number }
export interface Receipt {
  id: string;
  sha256: string;
  importedAt: string;
  members: Counts;
  orders: Counts;
  replayed: boolean;
}
export interface Member {
  externalMemberId: string;
  level: string;
  status: keyof typeof memberStatuses;
  joinedAt: string | null;
  expiresAt: string | null;
}
export interface Order {
  externalOrderId: string;
  externalMemberId: string | null;
  status: keyof typeof orderStatuses;
  currency: string;
  amount: string;
  orderedAt: string;
  sourceUpdatedAt: string;
  importId: string;
  sourceRow: number;
}
export interface OrderGroup {
  status: Order['status'];
  currency: string;
  orderCount: number;
  amount: string;
}
export interface Overview { orderCount: number; groups: OrderGroup[] }
export interface Page<T> { items: T[]; total: number; nextCursor: string | null }

export class CommerceError extends Error {
  constructor(public status: number, public data: { message?: string; traceId?: string; section?: string;
    row?: number; field?: string }) {
    super(data.message || '请求失败，请稍后重试');
  }
}

export async function commerceApi<T>(path: string, signal: AbortSignal,
  query: Record<string, string> = {}, body?: FormData): Promise<T> {
  const url = new URL('/api/commerce' + path, window.location.origin);
  for (const [field, value] of Object.entries(query)) {
    if (value) url.searchParams.set(field, value);
  }
  const response = await fetch(url, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: `Bearer ${sessionStorage.getItem('workpanel-token') ?? ''}` },
    signal,
    body,
  });
  const data = await response.json().catch(() => null);
  if (!response.ok || data === null) {
    throw new CommerceError(response.status, data ?? { message: '服务响应无效，请稍后重试' });
  }
  return data as T;
}
