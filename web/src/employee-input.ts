// Web 预校验与服务端 EmployeeInput 同步维护；保存仍以服务端结果为准。
export function nameError(raw: string): string {
  const name=raw.normalize('NFC').trim();
  return !/[\p{Cc}\p{Cf}]/u.test(raw) && [...name].length>=2 && [...name].length<=50 && /^[\p{L}][\p{L}\p{M}]*(?:[ ·'’\-][\p{L}][\p{L}\p{M}]*)*$/u.test(name) ? '' : '姓名须为2–50个字符，可用汉字、字母及姓名内部的空格、·、连字符或撇号，不能包含数字、表情或连续分隔符';
}
export function phoneError(phone: string): string {
  if(!/^[0-9]{11}$/.test(phone)) return '手机号须为11位数字';
  return /^(?:1(?:3[0-9]|4[57]|5[0-35-9]|6[2567]|7[0135-8]|8[0-9]|9[0-35-9])[0-9]{8}|1610[0-9]{7})$/.test(phone) ? '' : '手机号号段无效，请填写大陆公众移动手机号码';
}
