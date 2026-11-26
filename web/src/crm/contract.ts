// Candidate read contract for member A. Keep upstream mappings here until the
// backend teams publish their real API. Contract fixtures only live in tests.
export const kinds = ['memberships', 'benefits', 'orders', 'activities', 'services'] as const;
export type Kind = typeof kinds[number];
export type CustomerType = 'PERSONAL' | 'COMPANY';
export const labels: Record<Kind, string> = {
  memberships: '会员资格', benefits: '权益记录', orders: '商城订单', activities: '活动记录', services: '服务进度',
};
export const typeLabels: Record<CustomerType, string> = { PERSONAL: '个人客户', COMPANY: '企业客户' };
export const pageSize = 20;
export const searchLimit = 100;
export const isKind = (value: unknown): value is Kind => typeof value === 'string' && kinds.some(k => k === value);
export const isType = (value: unknown): value is CustomerType => value === 'PERSONAL' || value === 'COMPANY';
// Business IDs are stable URL segments, never URLs supplied by a payload.
export const isId = (value: unknown): value is string => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(value);
export const isCursor = (value: unknown): value is string => typeof value === 'string' && /^[\x21-\x7e]{1,256}$/.test(value);

export interface Customer {
  id: string; name: string; type: CustomerType; ownerName?: string; updatedAt?: string;
}
export interface RecordSummary {
  id: string; title: string; canOpen: boolean; status?: string; businessDate?: string;
  amountText?: string; validFrom?: string; validTo?: string; usageText?: string;
}
export type Section = { state: 'AVAILABLE'; items: RecordSummary[]; truncated: boolean } | { state: 'RESTRICTED' | 'UNAVAILABLE' };
export interface CustomerDetail extends Customer {
  contactName?: string; contactPhone?: string; contactEmail?: string;
  sections: Record<Kind, Section>;
}
export interface CustomerPage { items: Customer[]; total: number; nextCursor: string | null; previousCursor: string | null }
export interface RelatedRecord extends RecordSummary {
  description?: string; ownerName?: string; participantNames?: string[];
}

export class InvalidContract extends Error {}
function object(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new InvalidContract();
  return value as Record<string, unknown>;
}
function text(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}
function customer(value: unknown): Customer {
  const row = object(value), name = text(row.name);
  if (!isId(row.id) || !isType(row.type) || !name) throw new InvalidContract();
  return { id: row.id, name, type: row.type, ownerName: text(row.ownerName), updatedAt: text(row.updatedAt) };
}
function record(value: unknown, kind: Kind): RecordSummary {
  const row = object(value), title = text(row.title);
  if (!isId(row.id) || !title) throw new InvalidContract();
  return { id: row.id, title, canOpen: row.canOpen === true, status: text(row.status), businessDate: text(row.businessDate),
    ...(kind === 'orders' ? { amountText: text(row.amountText) } : {}),
    ...(['memberships', 'benefits'].includes(kind) ? { validFrom: text(row.validFrom), validTo: text(row.validTo), usageText: text(row.usageText) } : {}),
  };
}
function section(value: unknown, kind: Kind): Section {
  if (!value || typeof value !== 'object') return { state: 'UNAVAILABLE' };
  const row = object(value);
  if (row.state === 'RESTRICTED') return { state: 'RESTRICTED' };
  if (row.state !== 'AVAILABLE' || !Array.isArray(row.items)) return { state: 'UNAVAILABLE' };
  try { return { state: 'AVAILABLE', items: row.items.map(item => record(item, kind)), truncated: row.truncated === true }; }
  catch (error) { if (!(error instanceof InvalidContract)) throw error; return { state: 'UNAVAILABLE' }; }
}
function cursor(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (!isCursor(value)) throw new InvalidContract();
  return value;
}
export function parsePage(value: unknown): CustomerPage {
  const row = object(value);
  if (!Array.isArray(row.items) || row.items.length > pageSize || typeof row.total !== 'number' || !Number.isSafeInteger(row.total) || row.total < row.items.length) throw new InvalidContract();
  return { items: row.items.map(customer), total: row.total, nextCursor: cursor(row.nextCursor), previousCursor: cursor(row.previousCursor) };
}
export function parseCustomer(value: unknown, expectedId: string): CustomerDetail {
  const row = object(value), base = customer(row);
  if (base.id !== expectedId) throw new InvalidContract();
  const raw = row.sections == null ? {} : object(row.sections);
  const sections = Object.fromEntries(kinds.map(kind => [kind, section(raw[kind], kind)])) as Record<Kind, Section>;
  return { ...base, contactName: text(row.contactName), contactPhone: text(row.contactPhone), contactEmail: text(row.contactEmail), sections };
}
export function parseRecord(value: unknown, customerId: string, kind: Kind, expectedId: string): RelatedRecord {
  const row = object(value), base = record(row, kind);
  if (row.customerId !== customerId || row.kind !== kind || base.id !== expectedId) throw new InvalidContract();
  return { ...base, description: text(row.description), ownerName: text(row.ownerName),
    participantNames: Array.isArray(row.participantNames) ? row.participantNames.map(text).filter((x): x is string => x !== undefined) : undefined };
}
export function displayDate(value?: string) {
  if (!value) return '';
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '' : new Intl.DateTimeFormat('zh-CN', { timeZone: 'Asia/Shanghai', dateStyle: 'medium' }).format(date);
}
