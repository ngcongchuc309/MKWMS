const db = () => window.MKWMS_DB;
const state = () => window.MKWMS_STATE || {};
window.MKWMS_OPERATIONS_READY = true;
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const roleNames = {admin:'Quản trị viên',warehouse_manager:'Quản lý kho',warehouse_staff:'Nhân viên kho',sales:'Bán hàng',delivery:'Giao hàng',accounting:'Kế toán'};
const statusNames = {draft:'Bản nháp',pending_approval:'Chờ duyệt',approved:'Đã duyệt',posted:'Đã ghi sổ',cancelled:'Đã hủy',reversed:'Đã đảo',waiting:'Chờ giao',in_transit:'Đang giao',partial:'Giao một phần',delivered:'Đã giao',failed:'Giao thất bại',overdue:'Quá hạn'};
const date = v => v ? new Date(v).toLocaleDateString('vi-VN') : '—';
const datetime = v => v ? new Date(v).toLocaleString('vi-VN') : '—';
const qty = v => Number(v || 0).toLocaleString('vi-VN');
const toast = msg => window.toast?.(msg);
const activeRole = () => state().profile?.role || '';
const isAdmin = () => activeRole() === 'admin';
const isManager = () => ['admin','warehouse_manager'].includes(activeRole());
const canApproveOutbound = () => isManager() || state().profile?.can_approve_outbound === true;
const canWarehouse = () => ['admin','warehouse_manager','warehouse_staff'].includes(activeRole());
const product = id => state().products?.find(p => p.id === id);
const warehouse = id => state().warehouses?.find(w => w.id === id);
const partner = id => state().partners?.find(p => p.id === id);
const option = (value,label,selected='') => `<option value="${esc(value)}" ${String(value)===String(selected)?'selected':''}>${esc(label)}</option>`;
const field = (label,name,value='',type='text',attrs='') => `<div class="field"><label>${esc(label)}</label><input name="${esc(name)}" type="${type}" value="${esc(value)}" ${attrs}></div>`;
const selectField = (label,name,options,value='') => `<div class="field"><label>${esc(label)}</label><select name="${esc(name)}" required>${options.map(o=>option(o.value,o.label,value)).join('')}</select></div>`;
const safeRows = (headers, rows, actions='') => `<div class="tablewrap"><table class="table data-table"><thead><tr>${headers.map(h=>`<th>${esc(h)}</th>`).join('')}${actions?'<th>THAO TÁC</th>':''}</tr></thead><tbody>${rows.length?rows.map(r=>`<tr>${r.cells.map((v,i)=>`<td>${i===0?`<strong>${esc(v)}</strong>`:esc(v)}</td>`).join('')}${actions?`<td>${actions(r)}</td>`:''}</tr>`).join(''):`<tr><td colspan="${headers.length+(actions?1:0)}" class="emptyhint">Chưa có dữ liệu.</td></tr>`}</tbody></table></div>`;
const action = (name,id,label,css='') => `<button class="row-action ${css}" data-action="${esc(name)}" data-id="${esc(id)}">${esc(label)}</button>`;
function pageShell(id,title,subtitle,buttons,content){
  const root=document.getElementById('genericPage');
  root.innerHTML=`<div class="heading"><div><p class="eyebrow">MKWMS · Vận hành kho</p><h1>${esc(title)}</h1><p>${esc(subtitle)}</p></div><div class="actions">${buttons}</div></div>${content}`;
}
function filterBar(rows, placeholder='Tìm kiếm...'){
  return `<div class="table-tools"><div class="search"><input placeholder="${esc(placeholder)}" data-filter-table></div><span class="spacer"></span><span class="pill">${rows.length} bản ghi</span></div>`;
}
function renderItems(){
  const s=state(), stock=new Map();
  for(const b of s.balances||[]) stock.set(b.product_id,(stock.get(b.product_id)||0)+Number(b.on_hand_quantity||0));
  const rows=(s.products||[]).map(p=>({id:p.id,cells:[p.sku,p.name,p.category||'—',p.brand||'—',p.unit,qty(stock.get(p.id)),qty(p.minimum_stock),p.active?'Hoạt động':'Ngừng hoạt động']}));
  const head=action('new-product','','＋ Thêm');
  pageShell('items','Danh mục hàng hóa','Mã hàng, nhóm hàng, đơn vị, quy cách và tồn tối thiểu.',head+`<a class="btn" href="MKWMS_mau_nhap_hang_hoa.xlsx" download>↓ Tải mẫu Excel</a>`,`${filterBar(rows)}<article class="panel">${safeRows(['MÃ SKU','TÊN HÀNG','NHÓM','THƯƠNG HIỆU','ĐƠN VỊ','TỒN','TỐI THIỂU','TRẠNG THÁI'],rows,r=>`${action('edit-product',r.id,'Sửa')}${action('toggle-product',r.id,r.cells[7]==='Hoạt động'?'Ngừng bán':'Kích hoạt')}`)}</article>`);
}
function renderInventory(){
  const s=state(), rows=(s.balances||[]).map(b=>{const p=product(b.product_id),w=warehouse(b.warehouse_id);return {id:`${b.warehouse_id}|${b.product_id}|${b.location_code}|${b.lot_code}`,cells:[p?.sku||'—',p?.name||'—',w?.name||'—',b.location_code||'—',b.lot_code||'—',qty(b.on_hand_quantity),qty(b.reserved_quantity),qty(b.available_quantity),datetime(b.updated_at)]}});
  const controls=`${action('new-transfer','','⇄ Điều chuyển')}${action('new-adjustment','','± Kiểm kê / điều chỉnh')}`;
  const adjustments=(s.adjustments||[]).map(a=>({id:a.id,obj:a,cells:[a.document_code,warehouse(a.warehouse_id)?.name||'—',a.reason,date(a.created_at),statusNames[a.status]||a.status,s.profiles.find(p=>p.user_id===a.created_by)?.full_name||'—']}));
  const transfers=(s.transfers||[]).map(t=>({id:t.id,cells:[t.document_code,warehouse(t.from_warehouse_id)?.name||'—',warehouse(t.to_warehouse_id)?.name||'—',(t.stock_transfer_lines||[]).length,date(t.created_at),s.profiles.find(p=>p.user_id===t.created_by)?.full_name||'—']}));
  const movementSources=[...new Map((s.movements||[]).filter(m=>['stock_adjustment','stock_transfer','opening_balance'].includes(m.source_type)).map(m=>[`${m.source_type}:${m.source_id}`,m])).values()].filter(m=>!s.movements.some(x=>x.source_type==='reversal'&&x.source_id===m.source_id));
  const movementRows=movementSources.map(m=>({id:m.source_id,obj:m,cells:[m.source_type,m.source_id.slice(0,8),warehouse(m.warehouse_id)?.name||'—',product(m.product_id)?.sku||'—',date(m.created_at)]}));
  pageShell('inventory','Quản lý kho & tồn kho','Tra cứu tồn thực tế, đã giữ chỗ và khả dụng theo kho, mã hàng, lô và vị trí.',controls,`${filterBar(rows)}<article class="panel">${safeRows(['SKU','HÀNG HÓA','KHO','VỊ TRÍ','SỐ LÔ','THỰC TẾ','ĐÃ GIỮ','KHẢ DỤNG','CẬP NHẬT'],rows)}</article><div class="notice" style="margin-top:14px">Tồn khả dụng = Tồn thực tế − Đã giữ chỗ. Phiếu xuất được giữ chỗ khi duyệt; tồn chỉ giảm khi xác nhận xuất. Điều chỉnh tồn để sửa sai phiếu nhập/xuất đã ghi sổ.</div><article class="panel" style="margin-top:14px"><div class="panelhead"><div><h2>Phiếu kiểm kê / điều chỉnh</h2><p>Quản lý duyệt và ghi sổ điều chỉnh.</p></div></div>${safeRows(['MÃ PHIẾU','KHO','LÝ DO','NGÀY TẠO','TRẠNG THÁI','NGƯỜI TẠO'],adjustments,r=>r.obj.status==='pending_approval'&&isManager()?action('approve-adjustment',r.id,'Duyệt & ghi sổ','approve'):'—')}</article><article class="panel" style="margin-top:14px"><div class="panelhead"><div><h2>Lịch sử điều chuyển kho</h2><p>Giao dịch được ghi sổ nguyên tử ở cả kho xuất và kho nhận.</p></div></div>${safeRows(['MÃ PHIẾU','TỪ KHO','ĐẾN KHO','DÒNG HÀNG','NGÀY','NGƯỜI TẠO'],transfers)}</article><article class="panel" style="margin-top:14px"><div class="panelhead"><div><h2>Đảo giao dịch đã ghi sổ</h2><p>Chỉ điều chuyển, kiểm kê và tồn đầu kỳ; lý do bắt buộc. Phiếu nhập/xuất được sửa tồn bằng điều chỉnh đã duyệt.</p></div></div>${safeRows(['LOẠI NGUỒN','MÃ NGUỒN','KHO','SKU','NGÀY'],movementRows,r=>isManager()?action('reverse-transaction',r.id,'Đảo giao dịch'): '—')}</article>`);
}
function renderOrders(kind){
  const s=state(), inbound=kind==='inbound', data=inbound?s.inbounds:s.outbounds;
  const rows=(data||[]).map(o=>{
    const lines=inbound?o.inbound_order_lines:o.outbound_order_lines;
    return {id:o.document_code,obj:o,cells:[o.document_code,inbound?({supplier:'Nhập nhà cung cấp',return:'Nhập trả hàng',other:'Nhập khác'})[o.inbound_type]:({sale:'Xuất bán',internal:'Xuất nội bộ',other:'Xuất khác'})[o.outbound_type],inbound?(o.partners?.name||'—'):(o.partner_name||o.partners?.name||'—'),String(lines?.length||0),qty((lines||[]).reduce((a,l)=>a+Number(inbound?l.expected_quantity:l.requested_quantity),0)),date(o.created_on),o.created_by_profile?.full_name||'—',statusNames[o.status]||o.status]};
  });
  const buttons=action(inbound?'new-inbound':'new-outbound','',inbound?'＋ Tạo phiếu nhập':'＋ Tạo phiếu xuất');
  const headers=['MÃ PHIẾU','LOẠI','ĐỐI TÁC','DÒNG','TỔNG SL','NGÀY TẠO','NGƯỜI TẠO','TRẠNG THÁI'];
  const actions=r=>{
    const o=r.obj, acts=[action('order-detail',o.id,'Chi tiết')];
    if(inbound){
      if(o.status==='draft') acts.push(action('submit-inbound',o.id,'Gửi duyệt'));
      if(o.status==='pending_approval'&&isManager()) acts.push(action('approve-inbound',o.id,'Duyệt','approve'));
      if(o.status==='approved') acts.push(action('receive-inbound',o.id,'Nhận hàng'));
    } else {
      if(o.status==='draft') acts.push(action('submit-outbound',o.id,'Gửi duyệt'));
      if(o.status==='pending_approval'&&canApproveOutbound()) acts.push(action('approve-outbound',o.id,'Duyệt','approve'));
      if(o.status==='approved'&&canWarehouse()) acts.push(action('issue-outbound',o.id,'Xác nhận xuất'));
    }
    return acts.join('');
  };
  pageShell(kind, inbound?'Phiếu nhập kho':'Phiếu xuất kho',inbound?'Lập phiếu, duyệt và ghi nhận số lượng thực nhận.':'Lập phiếu, giữ hàng sau duyệt và xác nhận xuất từng phần.',buttons,`${filterBar(rows)}<article class="panel">${safeRows(headers,rows,actions)}</article>`);
}
function renderDelivery(){
  const s=state(), rows=(s.deliveries||[]).map(d=>({id:d.id,obj:d,cells:[d.delivery_code,d.outbound_orders?.document_code||'—',d.receiver_name||'—',d.carrier_name||'Chưa phân công',d.driver_name||'Chưa phân công',date(d.expected_delivery_date),statusNames[d.status]||d.status,datetime(d.updated_at)]}));
  pageShell('delivery','Theo dõi giao hàng','Cập nhật đơn vị vận chuyển, tài xế, tiến độ, số lượng thực nhận và lịch sử giao lại.',`<button class="btn" data-action="export-deliveries">↓ Xuất Excel</button>`,`${filterBar(rows)}<article class="panel">${safeRows(['MÃ GIAO','PHIẾU XUẤT','NGƯỜI NHẬN','ĐƠN VỊ VC','TÀI XẾ','DỰ KIẾN','TRẠNG THÁI','CẬP NHẬT'],rows,r=>`${action('edit-delivery',r.id,'Cập nhật')}${['partial','failed','overdue'].includes(r.obj.status)?action('retry-delivery',r.id,'Tạo lần giao lại'):''}${state().documents.filter(d=>d.delivery_order_id===r.id).map(d=>action('open-document',d.id,'Bằng chứng')).join('')}`)}</article>`);
}
function renderPartners(){
  const rows=(state().partners||[]).map(p=>({id:p.id,obj:p,cells:[p.partner_code,p.name,p.partner_type==='supplier'?'Nhà cung cấp':p.partner_type==='customer'?'Khách hàng':'Cả hai',p.tax_code||'—',p.contact_name||'—',p.phone||'—',p.email||'—',p.active?'Hoạt động':'Ngừng hoạt động']}));
  pageShell('partners','Khách hàng & nhà cung cấp','Thông tin đối tác được gắn với phiếu nhập, xuất và giao hàng.',action('new-partner','','＋ Thêm đối tác'),`${filterBar(rows)}<article class="panel">${safeRows(['MÃ','TÊN DOANH NGHIỆP','LOẠI','MST','NGƯỜI LIÊN HỆ','ĐIỆN THOẠI','EMAIL','TRẠNG THÁI'],rows,r=>`${action('partner-history',r.id,'Lịch sử')}${action('edit-partner',r.id,'Sửa')}${action('toggle-partner',r.id,r.obj.active?'Ngừng hoạt động':'Kích hoạt')}`)}</article>`);
}
function renderWarehouses(){
  const rows=(state().warehouses||[]).map(w=>({id:w.id,obj:w,cells:[w.code,w.name,w.address||'—',w.active?'Đang hoạt động':'Ngừng hoạt động']}));
  pageShell('warehouses','Danh sách kho','Quản lý các kho và trạng thái hoạt động.',action('new-warehouse','','＋ Thêm kho'),`${filterBar(rows)}<article class="panel">${safeRows(['MÃ KHO','TÊN KHO','ĐỊA CHỈ','TRẠNG THÁI'],rows,r=>`${action('edit-warehouse',r.id,'Sửa')}${action('toggle-warehouse',r.id,r.obj.active?'Ngừng hoạt động':'Kích hoạt')}`)}</article>`);
}
function renderUsers(){
  if(!isAdmin()) return pageShell('users','Người dùng & phân quyền','Chỉ quản trị viên mới xem và thay đổi phân quyền.','',`<div class="notice">Bạn không có quyền quản trị người dùng.</div>`);
  const s=state(), rows=(s.profiles||[]).map(p=>{
    const scopes=(s.userWarehouses||[]).filter(x=>x.user_id===p.user_id).map(x=>warehouse(x.warehouse_id)?.name).filter(Boolean);
    const approval=p.can_approve_outbound?'Được cấp riêng':['admin','warehouse_manager'].includes(p.role)?'Theo vai trò':'Không';
    return {id:p.user_id,obj:p,cells:[p.full_name||'—',p.email||'—',roleNames[p.role]||p.role,scopes.length?scopes.join(', '):(p.role==='admin'?'Tất cả kho':'Chưa phân kho'),approval,p.active?'Đang hoạt động':'Đã khóa']};
  });
  pageShell('users','Người dùng & phân quyền','Tạo tài khoản Auth trong Supabase trước, sau đó gán vai trò, phạm vi kho và quyền duyệt phiếu xuất.',`<a class="btn" target="_blank" rel="noreferrer" href="https://supabase.com/dashboard/project/cstllaucehmhqoxdygdo/auth/users">Quản lý tài khoản Auth ↗</a>`,`${filterBar(rows)}<article class="panel">${safeRows(['NGƯỜI DÙNG','EMAIL','VAI TRÒ','PHẠM VI KHO','DUYỆT PHIẾU XUẤT','TRẠNG THÁI'],rows,r=>r.id===s.user.id?'Tài khoản hiện tại':action('edit-user',r.id,'Phân quyền'))}</article><div class="notice" style="margin-top:14px">Quản trị viên và quản lý kho có quyền duyệt theo vai trò. Có thể cấp riêng quyền duyệt phiếu xuất cho người dùng khác; quyền này chỉ áp dụng trong phạm vi kho được phân công.</div><article class="panel" style="margin-top:14px"><div class="panelhead"><div><h2>Nhật ký kiểm toán</h2><p>Lưu người tạo, sửa, duyệt và ghi sổ; không lưu nội dung bí mật.</p></div></div>${safeRows(['THỜI GIAN','NGƯỜI THỰC HIỆN','THAO TÁC','ĐỐI TƯỢNG','THAY ĐỔI'],(s.audit||[]).map(a=>({id:a.id,cells:[datetime(a.created_at),a.actor?.full_name||'—',a.action,`${a.entity_type} · ${a.entity_id||''}`,Object.keys(a.details?.changed_fields||{}).join(', ')||JSON.stringify(a.details||{})]})))}</article>`);
}
function renderReports(){
  const s=state(), low=(s.products||[]).filter(p=>{
    const total=(s.balances||[]).filter(b=>b.product_id===p.id).reduce((a,b)=>a+Number(b.on_hand_quantity||0),0);return p.active&&total<Number(p.minimum_stock||0);
  });
  const delivered=(s.deliveries||[]).filter(d=>d.status==='delivered').length, late=(s.deliveries||[]).filter(d=>d.status==='overdue'||(d.expected_delivery_date&&new Date(`${d.expected_delivery_date}T23:59:59`)<new Date()&&!['delivered','failed'].includes(d.status))).length;
  const panels=[['Nhập — xuất — tồn','Tồn thực tế, đã giữ và khả dụng theo kho / SKU.','export-stock'],['Thẻ kho theo kỳ','Sổ giao dịch đã ghi sổ theo khoảng ngày.','export-ledger'],['Hàng dưới định mức',`${low.length} SKU đang dưới tồn tối thiểu.`,'export-low'],['Hàng chậm luân chuyển','SKU không phát sinh hoặc ít giao dịch trong 90 ngày.','export-slow'],['Giao hàng',`${delivered} giao thành công · ${late} trễ hạn; kèm giao thiếu.`,'export-deliveries']];
  const cards=panels.map(([t,d,a])=>'<article class="panel report-card"><div class="panelhead"><div><h2>'+esc(t)+'</h2><p>'+esc(d)+'</p></div></div><button class="btn" data-action="'+esc(a)+'">Xuất báo cáo</button></article>').join('');
  const buttons='<button class="btn" data-action="export-all-reports">↓ Xuất Excel</button>';
  const filters='<article class="panel report-filters"><div class="panelhead"><div><h2>Bộ lọc báo cáo</h2><p>Để trống ngày nếu muốn lấy toàn bộ kỳ dữ liệu hiện có.</p></div></div><div class="formgrid">'+field('Từ ngày','report_from','','date')+field('Đến ngày','report_to','','date')+selectField('Kho','report_warehouse',[{value:'',label:'Tất cả kho'},...s.warehouses.map(w=>({value:w.id,label:w.name}))],'')+selectField('SKU','report_product',[{value:'',label:'Tất cả SKU'},...s.products.map(p=>({value:p.id,label:p.sku+' · '+p.name}))],'')+'</div></article>';
  pageShell('reports','Báo cáo & thống kê','Lọc theo thời gian, kho và SKU; tải báo cáo Excel từ dữ liệu đã ghi sổ.',buttons,filters+'<div class="metric-grid">'+cards+'</div>');
}
function renderImports(){
  const importUi=window.importWorkspaceMarkup?.()||'';
  const s=state();
  const history=safeRows(['SKU','HÀNG HÓA','TỒN KHO HIỆN TẠI'],s.products.slice(0,20).map(p=>({id:p.id,cells:[p.sku,p.name,qty(s.balances.filter(b=>b.product_id===p.id).reduce((n,b)=>n+Number(b.on_hand_quantity),0))]})));
  const buttons='<button class="btn" data-action="download-opening-template">↓ Mẫu tồn đầu kỳ</button>';
  const content=importUi+'<article class="import-card"><div class="import-top"><div><h2>Nhập tồn đầu kỳ</h2><p>Chỉ áp dụng cho ô tồn chưa được ghi nhận; không ghi đè số tồn hiện có.</p></div></div><div class="upload-row"><input type="file" accept=".xlsx,.xls" data-opening-file><span class="file-name" data-opening-name>Chưa chọn tệp</span><button class="btn primary" data-action="preview-opening">Kiểm tra dữ liệu</button></div><div class="import-status" data-opening-status></div><div data-opening-preview></div></article><article class="panel"><div class="panelhead"><div><h2>Lịch sử giao dịch nhập dữ liệu</h2><p>Dữ liệu được tải từ Supabase.</p></div></div>'+history+'</article>';
  pageShell('imports','Nhập dữ liệu Excel','Tải mẫu, xem trước lỗi và chỉ ghi dữ liệu sau khi xác nhận.',buttons,content);
}
function renderPage(id){
  if(!state().profile)return;
  if(id==='items')return renderItems(); if(id==='inventory')return renderInventory();
  if(id==='inbound'||id==='outbound')return renderOrders(id); if(id==='delivery')return renderDelivery();
  if(id==='partners')return renderPartners(); if(id==='warehouses')return renderWarehouses();
  if(id==='users')return renderUsers(); if(id==='reports')return renderReports(); if(id==='imports')return renderImports();
}

const pageDefs=window.MKWMS_PAGES;
if(pageDefs && !pageDefs.warehouses) pageDefs.warehouses={title:'Danh sách kho',sub:'Quản lý kho hàng.',button:'＋ Thêm kho',columns:[],rows:[]};
if(!document.querySelector('#navigation [data-page="warehouses"]')) document.querySelector('#navigation')?.insertAdjacentHTML('beforeend','<button data-page="warehouses">▦ Kho hàng</button>');
const baseNavigate=window.navigate;
if(baseNavigate) window.navigate=(id)=>{baseNavigate(id);renderPage(id)};
window.addEventListener('mkwms:workspace-loaded',e=>{if(e.detail) window.MKWMS_STATE=e.detail;const id=document.querySelector('.nav button.active')?.dataset.page||'dashboard';renderPage(id);});

const baseOpenModal=window.openModal;
window.openModal=(title,desc,type='')=>{
  document.getElementById('modalSubmit').hidden=false;
  if(['inbound','outbound'].includes(type)) {
    baseOpenModal(title,desc,type);
    if(type==='outbound')document.getElementById('itemRows')?.insertAdjacentHTML('afterend','<p class="notice">Để trống vị trí/lô để hệ thống tự giữ hàng từ các vị trí còn tồn khi duyệt. Nếu chọn vị trí, hệ thống sẽ giữ đúng vị trí đó.</p>');
    document.getElementById('modalSubmit').textContent='Gửi duyệt';
    document.getElementById('modalSubmit').onclick=()=>window.saveModal('submit');
    document.getElementById('modalSaveDraft').hidden=false;
    document.getElementById('modalSaveDraft').onclick=()=>window.saveModal('draft');
    return;
  }
  window.MKWMS_MODAL_TYPE=`ops:${type}`;window.MKWMS_EDIT_ID='';
  const modal=document.getElementById('modalback');document.getElementById('modalTitle').textContent=title;document.getElementById('modalDesc').textContent=desc;
  document.getElementById('modalSaveDraft').hidden=true;document.getElementById('modalSubmit').textContent='Lưu';
  document.getElementById('modalbody').innerHTML=makeForm(type,null);modal.classList.add('open');
};
window.closeModal=()=>document.getElementById('modalback').classList.remove('open');
function productOptions(selected=''){return state().products.filter(p=>p.active).map(p=>option(p.id,`${p.sku} · ${p.name}`,selected)).join('')}
function warehouseOptions(selected=''){return state().warehouses.filter(w=>w.active).map(w=>option(w.id,w.name,selected)).join('')}
function lineEditor(kind,existing=[]){
  const isReceipt=kind==='receive', isIssue=kind==='issue',isDelivery=kind==='delivery';
  const order=existing;
  const lines=isReceipt?order.inbound_order_lines:isIssue?order.outbound_order_lines:isDelivery?order.outbound_orders?.outbound_order_lines:[];
  return `<div class="formsection">HÀNG HÓA</div><div data-ops-lines>${(lines||[]).map(l=>{
    const p=product(l.product_id), deliveredElsewhere=isDelivery?state().deliveryLines.filter(x=>x.outbound_order_line_id===l.id&&x.delivery_order_id!==order.id).reduce((a,x)=>a+Number(x.quantity_delivered),0):0, remaining=isReceipt?Number(l.expected_quantity)-Number(l.received_quantity||0):isIssue?Number(l.reserved_quantity||0):Math.max(0,Number(l.issued_quantity||0)-deliveredElsewhere);
    const qtyLabel=isReceipt?'Thực nhận':isIssue?'Số lượng xuất':'Số nhận trong lần giao';
    const deliveryQty=isDelivery?Number(state().deliveryLines.find(x=>x.delivery_order_id===order.id&&x.outbound_order_line_id===l.id)?.quantity_delivered||0):remaining;
    return `<div class="ops-line" data-line-id="${esc(l.id)}" data-product-id="${esc(l.product_id)}"><div><b>${esc(p?.sku||'—')} · ${esc(p?.name||'—')}</b><small>${isReceipt?`${qty(l.received_quantity||0)} / ${qty(l.expected_quantity)} đã nhận`:isIssue?`Còn giữ ${qty(remaining)}`:`Tổng đã giao các lần: ${qty(Number(l.issued_quantity)-remaining)} · Lần này tối đa ${qty(remaining)}`}</small></div><div class="field"><label>${qtyLabel}</label><input type="number" min="0" max="${remaining}" value="${deliveryQty}" data-line-qty></div><div class="field"><label>Vị trí</label><input value="${esc(l.location_code||'')}" data-line-location></div><div class="field"><label>Số lô</label><input value="${esc(l.lot_code||'')}" data-line-lot></div></div>`;
  }).join('')||'<div class="emptyhint">Phiếu không có dòng hàng.</div>'}</div>`;
}
function makeForm(type,record){
  const s=state(), p=record||{};
  if(type==='product')return `<form id="opsForm" class="formgrid">${field('SKU','sku',p.sku||'','text','required')}${field('Tên hàng','name',p.name||'','text','required')}${field('Nhóm hàng','category',p.category||'')}${field('Thương hiệu','brand',p.brand||'')}${field('Đơn vị tính','unit',p.unit||'','text','required')}${field('Quy cách đóng gói','package_spec',p.package_spec||'')}${field('Tồn tối thiểu','minimum_stock',p.minimum_stock||0,'number','min="0" step="1" required')}<div class="field"><label>Trạng thái</label><select name="active">${option('true','Hoạt động',String(p.active!==false))}${option('false','Ngừng hoạt động',String(p.active===false))}</select></div></form>`;
  if(type==='partner')return `<form id="opsForm" class="formgrid">${field('Mã đối tác','partner_code',p.partner_code||'','text','required')}${selectField('Loại đối tác','partner_type',[{value:'customer',label:'Khách hàng'},{value:'supplier',label:'Nhà cung cấp'},{value:'both',label:'Cả hai'}],p.partner_type||'supplier')}${field('Tên doanh nghiệp','name',p.name||'','text','required')}${field('Mã số thuế','tax_code',p.tax_code||'')}${field('Địa chỉ','address',p.address||'')}${field('Người liên hệ','contact_name',p.contact_name||'')}${field('Điện thoại','phone',p.phone||'','tel')}${field('Email','email',p.email||'','email')}<div class="field"><label>Trạng thái</label><select name="active">${option('true','Hoạt động',String(p.active!==false))}${option('false','Ngừng hoạt động',String(p.active===false))}</select></div></form>`;
  if(type==='warehouse')return `<form id="opsForm" class="formgrid">${field('Mã kho','code',p.code||'','text','required')}${field('Tên kho','name',p.name||'','text','required')}${field('Địa chỉ','address',p.address||'')}<div class="field"><label>Trạng thái</label><select name="active">${option('true','Hoạt động',String(p.active!==false))}${option('false','Ngừng hoạt động',String(p.active===false))}</select></div></form>`;
  if(type==='user'){
    const uid=p.user_id||'';const selected=new Set(s.userWarehouses.filter(x=>x.user_id===uid).map(x=>x.warehouse_id));
    return `<form id="opsForm">${field('Auth User UID','target_user',uid,'text','required')}${field('Tên người dùng','target_full_name',p.full_name||'','text','required')}<div class="formgrid">${selectField('Vai trò','target_role',Object.entries(roleNames).map(([value,label])=>({value,label})),p.role||'warehouse_staff')}<div class="field"><label>Trạng thái</label><select name="target_active">${option('true','Đang hoạt động',String(p.active!==false))}${option('false','Đã khóa',String(p.active===false))}</select></div></div><div class="field"><label>Phạm vi kho</label><div class="check-grid">${s.warehouses.map(w=>`<label class="check-option"><input type="checkbox" name="target_warehouses" value="${esc(w.id)}" ${selected.has(w.id)?'checked':''}><span>${esc(w.name)}</span></label>`).join('')}</div></div><div class="field"><label class="check-option"><input type="checkbox" name="target_can_approve_outbound" ${p.can_approve_outbound?'checked':''}><span>Cho phép duyệt phiếu xuất</span></label><small>Quản trị viên và quản lý kho đã có quyền theo vai trò; quyền cấp riêng vẫn bị giới hạn trong các kho đã chọn.</small></div><p class="notice">Tài khoản Auth phải được tạo trước trong Supabase. Thay đổi quyền được ghi vào nhật ký kiểm toán.</p></form>`;
  }
  if(type==='transfer')return `<form id="opsForm">${field('Mã phiếu điều chuyển','document_code',p.document_code||window.nextRef?.('DC',[] )||'DC-'+Date.now(),'text','required')}<div class="formgrid">${selectField('Kho xuất','from_warehouse_id',s.warehouses.filter(w=>w.active).map(w=>({value:w.id,label:w.name})), '')}${selectField('Kho nhận','to_warehouse_id',s.warehouses.filter(w=>w.active).map(w=>({value:w.id,label:w.name})), '')}</div><div class="formsection">HÀNG HÓA CHUYỂN</div><div data-transfer-lines>${transferLine()}</div><button type="button" class="addline" data-action="add-transfer-line">＋ Thêm hàng</button></form>`;
  if(type==='adjustment')return `<form id="opsForm">${field('Mã kiểm kê','document_code','KK-'+new Date().getFullYear()+'-'+String(Date.now()).slice(-6),'text','required')}${selectField('Kho','warehouse_id',s.warehouses.filter(w=>w.active).map(w=>({value:w.id,label:w.name})), '')}${field('Lý do','reason','','text','required')}<div class="formsection">SỐ LƯỢNG ĐẾM THỰC TẾ</div><div data-adjust-lines>${adjustLine()}</div><button type="button" class="addline" data-action="add-adjust-line">＋ Thêm SKU</button><p class="notice">Yêu cầu sẽ chờ quản lý duyệt. Khi duyệt, số tồn sẽ cập nhật bằng số lượng đã kiểm đếm.</p></form>`;
  if(type==='receive'||type==='issue')return `<form id="opsForm"><div class="notice">${type==='receive'?'Nhập số lượng thực nhận; để 0 nếu chưa nhận dòng đó. Có thể ghi nhận nhiều đợt.':'Nhập số lượng xuất trong đợt này; không vượt phần hàng đang giữ chỗ.'}</div>${lineEditor(type,record)}</form>`;
  if(type==='delivery'){
    const d=p, out=s.outbounds.find(o=>o.id===d.outbound_order_id);
    return `<form id="opsForm">${field('Ngày dự kiến giao','expected_delivery_date',d.expected_delivery_date||'','date')}<div class="formgrid">${field('Đơn vị vận chuyển','carrier_name',d.carrier_name||'')}${field('Tên tài xế','driver_name',d.driver_name||'')}${field('SĐT tài xế','driver_phone',d.driver_phone||'','tel')}${field('Biển số xe','vehicle_plate',d.vehicle_plate||'')}${field('Người nhận thực tế','received_by',d.received_by||'')}${field('Thời gian giao','actual_delivery_at',d.actual_delivery_at?new Date(d.actual_delivery_at).toISOString().slice(0,16):'','datetime-local')}</div>${selectField('Trạng thái giao','status',[{value:'waiting',label:'Chờ giao'},{value:'in_transit',label:'Đang giao'},{value:'partial',label:'Giao một phần'},{value:'delivered',label:'Đã giao'},{value:'failed',label:'Giao thất bại'},{value:'overdue',label:'Quá hạn'}],d.status)}${field('Liên kết bằng chứng giao hàng','proof_path',d.proof_path||'','url')}<div class="field"><label>Tải ảnh / PDF bằng chứng (tối đa 20 MB)</label><input type="file" name="proof_file" accept="application/pdf,image/jpeg,image/png,image/webp"></div>${lineEditor('delivery',d)}<input type="hidden" name="delivery_id" value="${esc(d.id)}"><input type="hidden" name="outbound_id" value="${esc(out?.id||d.outbound_order_id)}"></form>`;
  }
  return '<form id="opsForm"></form>';
}
function transferLine(){return `<div class="ops-line" data-transfer-line><div class="field"><label>Hàng hóa</label><select name="product_id" required><option value="">Chọn SKU</option>${productOptions()}</select></div><div class="field"><label>Số lượng</label><input name="quantity" type="number" min="1" step="1" required></div><div class="field"><label>Vị trí nguồn</label><input name="from_location_code"></div><div class="field"><label>Lô nguồn</label><input name="from_lot_code"></div><div class="field"><label>Vị trí đích</label><input name="to_location_code"></div><div class="field"><label>Lô đích</label><input name="to_lot_code"></div><button type="button" class="remove" data-remove-line>×</button></div>`}
function adjustLine(){return `<div class="ops-line" data-adjust-line><div class="field"><label>Hàng hóa</label><select name="product_id" required><option value="">Chọn SKU</option>${productOptions()}</select></div><div class="field"><label>Vị trí</label><input name="location_code"></div><div class="field"><label>Số lô</label><input name="lot_code"></div><div class="field"><label>Số đếm thực tế</label><input name="counted_quantity" type="number" min="0" step="1" required></div><button type="button" class="remove" data-remove-line>×</button></div>`}

function editModal(type,record){
  const modal=document.getElementById('modalback');window.MKWMS_MODAL_TYPE=`ops:${type}`;window.MKWMS_EDIT_ID=record?.id||'';
  document.getElementById('modalTitle').textContent=({product:record?'Sửa hàng hóa':'Thêm hàng hóa',partner:record?'Sửa đối tác':'Thêm đối tác',warehouse:record?'Sửa kho':'Thêm kho',user:'Phân quyền người dùng',receive:'Nhận hàng',issue:'Xác nhận xuất',delivery:'Cập nhật giao hàng',transfer:'Điều chuyển kho',adjustment:'Tạo phiếu kiểm kê'})[type]||'Cập nhật';
  document.getElementById('modalDesc').textContent=type==='user'?'Chỉ thay đổi quyền MKWMS; tài khoản và mật khẩu được quản lý trong Supabase Auth.':'Thông tin được lưu vào cơ sở dữ liệu MKWMS.';
  document.getElementById('modalSaveDraft').hidden=true;document.getElementById('modalSubmit').textContent=type==='receive'?'Ghi nhận nhập':type==='issue'?'Xác nhận xuất':type==='delivery'?'Lưu giao hàng':'Lưu';
  document.getElementById('modalbody').innerHTML=makeForm(type,record);modal.classList.add('open');document.getElementById('modalSubmit').onclick=()=>window.saveModal('submit');
}

const baseSave=window.MKWMS_SAVE_ORDER_MODAL||window.saveModal;
window.saveModal=async actionValue=>{
  if(!String(window.MKWMS_MODAL_TYPE||'').startsWith('ops:')) return (window.MKWMS_SAVE_ORDER_MODAL||baseSave)?.(actionValue);
  const form=document.getElementById('opsForm');if(!form||!form.reportValidity())return;
  const type=window.MKWMS_MODAL_TYPE.slice(4), fd=new FormData(form), client=db(), current=state(), uid=current.user.id;
  const submitButton=document.getElementById('modalSubmit'), draftButton=document.getElementById('modalSaveDraft');
  if(submitButton)submitButton.disabled=true;if(draftButton)draftButton.disabled=true;
  const saved=async promise=>{const {error}=await promise;if(error)throw error;await window.MKWMS_REFRESH();window.closeModal();toast('Đã lưu thay đổi.');};
  try{
    if(type==='product'){
      const row={sku:String(fd.get('sku')).trim(),name:String(fd.get('name')).trim(),category:String(fd.get('category')||''),brand:String(fd.get('brand')||''),unit:String(fd.get('unit')).trim(),package_spec:String(fd.get('package_spec')||''),minimum_stock:Number(fd.get('minimum_stock')||0),active:fd.get('active')==='true',updated_by:uid};
      if(window.MKWMS_EDIT_ID) await saved(client.from('products').update(row).eq('id',window.MKWMS_EDIT_ID));else await saved(client.from('products').insert({...row,created_by:uid}));return;
    }
    if(type==='partner'){
      const row={partner_code:String(fd.get('partner_code')).trim(),partner_type:fd.get('partner_type'),name:String(fd.get('name')).trim(),tax_code:String(fd.get('tax_code')||''),address:String(fd.get('address')||''),contact_name:String(fd.get('contact_name')||''),phone:String(fd.get('phone')||''),email:String(fd.get('email')||''),active:fd.get('active')==='true'};
      if(window.MKWMS_EDIT_ID) await saved(client.from('partners').update(row).eq('id',window.MKWMS_EDIT_ID));else await saved(client.from('partners').insert(row));return;
    }
    if(type==='warehouse'){
      if(!isAdmin())throw new Error('Chỉ quản trị viên được quản lý kho.');
      const row={code:String(fd.get('code')).trim().toUpperCase(),name:String(fd.get('name')).trim(),address:String(fd.get('address')||''),active:fd.get('active')==='true'};
      if(window.MKWMS_EDIT_ID) await saved(client.from('warehouses').update(row).eq('id',window.MKWMS_EDIT_ID));else await saved(client.from('warehouses').insert(row));return;
    }
    if(type==='user'){
      const warehouses=fd.getAll('target_warehouses');await saved(client.rpc('admin_set_user_profile',{target_user:fd.get('target_user'),target_full_name:fd.get('target_full_name'),target_role:fd.get('target_role'),target_active:fd.get('target_active')==='true',target_warehouses:warehouses,target_can_approve_outbound:fd.get('target_can_approve_outbound')==='on'}));return;
    }
    if(type==='transfer'){
      const lines=[...form.querySelectorAll('[data-transfer-line]')].map(row=>({product_id:row.querySelector('[name="product_id"]').value,quantity:Number(row.querySelector('[name="quantity"]').value),from_location_code:row.querySelector('[name="from_location_code"]').value.trim(),from_lot_code:row.querySelector('[name="from_lot_code"]').value.trim(),to_location_code:row.querySelector('[name="to_location_code"]').value.trim(),to_lot_code:row.querySelector('[name="to_lot_code"]').value.trim()}));
      if(lines.some(x=>!x.product_id||!Number.isInteger(x.quantity)||x.quantity<=0))throw new Error('Chọn hàng hóa và số lượng nguyên dương cho từng dòng.');
      await saved(client.rpc('transfer_stock',{from_warehouse:fd.get('from_warehouse_id'),to_warehouse:fd.get('to_warehouse_id'),transfer_code:fd.get('document_code'),transfer_lines:lines}));return;
    }
    if(type==='adjustment'){
      const lines=[...form.querySelectorAll('[data-adjust-line]')].map(row=>({product_id:row.querySelector('[name="product_id"]').value,location_code:row.querySelector('[name="location_code"]').value.trim(),lot_code:row.querySelector('[name="lot_code"]').value.trim(),counted_quantity:Number(row.querySelector('[name="counted_quantity"]').value)}));
      if(lines.some(x=>!x.product_id||!Number.isInteger(x.counted_quantity)||x.counted_quantity<0))throw new Error('Chọn hàng hóa và nhập số đếm nguyên không âm.');
      await saved(client.rpc('create_stock_adjustment',{target_warehouse:fd.get('warehouse_id'),adjustment_code:fd.get('document_code'),adjustment_reason:fd.get('reason'),adjustment_lines:lines}));return;
    }
    if(type==='receive'){
      const order=current.inbounds.find(x=>x.id===window.MKWMS_EDIT_ID);if(!order)throw new Error('Không tìm thấy phiếu nhập.');
      const lines=[...form.querySelectorAll('[data-line-id]')].map(row=>({line_id:row.dataset.lineId,quantity:Number(row.querySelector('[data-line-qty]').value),location_code:row.querySelector('[data-line-location]').value.trim(),lot_code:row.querySelector('[data-line-lot]').value.trim()})).filter(x=>x.quantity>0);
      if(!lines.length)throw new Error('Nhập ít nhất một số lượng thực nhận lớn hơn 0.');
      const {error}=await client.rpc('post_inbound_receipt',{target_order:order.id,idempotency_key:crypto.randomUUID(),receipt_lines:lines});if(error)throw error;await window.MKWMS_REFRESH();window.closeModal();toast('Đã ghi nhận hàng nhận vào tồn kho.');return;
    }
    if(type==='issue'){
      const order=current.outbounds.find(x=>x.id===window.MKWMS_EDIT_ID);if(!order)throw new Error('Không tìm thấy phiếu xuất.');
      const lines=[...form.querySelectorAll('[data-line-id]')].map(row=>({line_id:row.dataset.lineId,quantity:Number(row.querySelector('[data-line-qty]').value)})).filter(x=>x.quantity>0);
      if(!lines.length)throw new Error('Nhập ít nhất một số lượng xuất lớn hơn 0.');
      const {error}=await client.rpc('post_outbound_issue',{target_order:order.id,idempotency_key:crypto.randomUUID(),issue_lines:lines});if(error)throw error;await window.MKWMS_REFRESH();window.closeModal();toast('Đã xác nhận xuất hàng; tồn kho đã được cập nhật.');return;
    }
    if(type==='delivery'){
      const d=current.deliveries.find(x=>x.id===fd.get('delivery_id'));if(!d)throw new Error('Không tìm thấy lệnh giao.');
      let proofPath=fd.get('proof_path')||'';const proofFile=fd.get('proof_file');if(proofFile instanceof File&&proofFile.size){const order=current.outbounds.find(x=>x.id===d.outbound_order_id);if(!order)throw new Error('Không tìm thấy phiếu xuất liên quan.');proofPath=await uploadOrderDocument(proofFile,order.warehouse_id,d.id,'delivery');form.elements.proof_path.value=proofPath;form.elements.proof_file.value='';}
      const lines=[...form.querySelectorAll('[data-line-id]')].map(row=>({line_id:row.dataset.lineId,quantity:Number(row.querySelector('[data-line-qty]').value)})).filter(x=>x.quantity>0);
      const stamp=fd.get('actual_delivery_at')?new Date(fd.get('actual_delivery_at')).toISOString():null;
      const {error}=await client.rpc('update_delivery_and_record_attempt',{target_delivery:d.id,expected_date:fd.get('expected_delivery_date')||null,carrier:fd.get('carrier_name')||'',driver:fd.get('driver_name')||'',driver_contact:fd.get('driver_phone')||'',vehicle:fd.get('vehicle_plate')||'',next_status:fd.get('status'),received_name:fd.get('received_by')||'',actual_time:stamp,proof:proofPath,delivered_lines:lines});if(error)throw error;await window.MKWMS_REFRESH();window.closeModal();toast('Đã cập nhật trạng thái và lịch sử giao hàng.');return;
    }
  }catch(error){toast(error?.message||'Không thể lưu dữ liệu.');}
  finally{if(submitButton)submitButton.disabled=false;if(draftButton)draftButton.disabled=false;}
};

function openReceive(o){window.MKWMS_EDIT_ID=o.id;editModal('receive',o)}
function openIssue(o){window.MKWMS_EDIT_ID=o.id;editModal('issue',o)}
function openPartnerHistory(id){
  const s=state(),p=s.partners.find(x=>x.id===id);if(!p)return;
  const inRows=s.inbounds.filter(o=>o.supplier_id===id).map(o=>({id:o.id,cells:[o.document_code,date(o.created_on),statusNames[o.status]||o.status,qty((o.inbound_order_lines||[]).reduce((n,l)=>n+Number(l.expected_quantity),0))]}));
  const outRows=s.outbounds.filter(o=>o.partner_id===id).map(o=>({id:o.id,cells:[o.document_code,date(o.created_on),statusNames[o.status]||o.status,qty((o.outbound_order_lines||[]).reduce((n,l)=>n+Number(l.requested_quantity),0))]}));
  document.getElementById('modalTitle').textContent=`Lịch sử · ${p.name}`;document.getElementById('modalDesc').textContent='Phiếu nhập, phiếu xuất và giao hàng liên quan.';document.getElementById('modalSaveDraft').hidden=true;document.getElementById('modalSubmit').textContent='Đóng';document.getElementById('modalSubmit').onclick=window.closeModal;
  const deliveries=s.deliveries.filter(d=>s.outbounds.some(o=>o.id===d.outbound_order_id&&o.partner_id===id)).map(d=>({id:d.id,cells:[d.delivery_code,d.outbound_orders?.document_code||'—',date(d.expected_delivery_date),statusNames[d.status]||d.status]}));
  document.getElementById('modalbody').innerHTML='<h4>Phiếu nhập</h4>'+safeRows(['MÃ PHIẾU','NGÀY TẠO','TRẠNG THÁI','TỔNG SL'],inRows)+'<h4>Phiếu xuất</h4>'+safeRows(['MÃ PHIẾU','NGÀY TẠO','TRẠNG THÁI','TỔNG SL'],outRows)+'<h4>Giao hàng</h4>'+safeRows(['MÃ GIAO','PHIẾU XUẤT','DỰ KIẾN','TRẠNG THÁI'],deliveries);window.MKWMS_MODAL_TYPE='';document.getElementById('modalback').classList.add('open');
}
async function uploadOrderDocument(file,warehouseId,parentId,kind){
  const mimeByExtension={pdf:'application/pdf',jpg:'image/jpeg',jpeg:'image/jpeg',png:'image/png',webp:'image/webp',docx:'application/vnd.openxmlformats-officedocument.wordprocessingml.document',xlsx:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'};
  const extension=file.name.split('.').pop().toLowerCase(),mime=file.type||mimeByExtension[extension]||'';
  const allowed=Object.values(mimeByExtension);
  if(!allowed.includes(mime)||file.size>20*1024*1024)throw new Error('Chọn PDF, JPG, PNG, WEBP, DOCX hoặc XLSX dưới 20 MB.');
  const clean=file.name.replace(/[^\p{L}\p{N}._-]+/gu,'_').slice(-120),path=`${warehouseId}/${parentId}/${crypto.randomUUID()}-${clean}`;
  const client=db(),{error:uploadError}=await client.storage.from('mkwms-documents').upload(path,file,{upsert:false,contentType:mime});if(uploadError)throw uploadError;
  const row={warehouse_id:warehouseId,inbound_order_id:kind==='inbound'?parentId:null,delivery_order_id:kind==='delivery'?parentId:null,file_name:file.name,mime_type:mime,file_size:file.size,storage_path:path,uploaded_by:state().user.id};
  const {error}=await client.from('order_documents').insert(row);if(error)throw error;
  return path;
}
function printOrder(o,inbound){
  const lines=inbound?o.inbound_order_lines:o.outbound_order_lines, body=lines.map(l=>`<tr><td>${esc(product(l.product_id)?.sku)}</td><td>${esc(product(l.product_id)?.name)}</td><td>${qty(inbound?l.expected_quantity:l.requested_quantity)}</td><td>${qty(inbound?l.received_quantity:l.issued_quantity)}</td></tr>`).join('');
  const w=window.open('','_blank');if(!w)return toast('Trình duyệt đang chặn cửa sổ in.');
  w.document.write(`<html lang="vi"><meta charset="utf-8"><title>${esc(o.document_code)}</title><style>body{font:14px Arial;padding:32px;color:#172b47}h1{font-size:20px}table{width:100%;border-collapse:collapse;margin-top:20px}th,td{border:1px solid #ccd5e2;padding:9px;text-align:left}button{padding:8px 12px}@media print{button{display:none}}</style><h1>Minh Khanh Warehouse · ${inbound?'PHIẾU NHẬP':'PHIẾU XUẤT'}</h1><p>Mã phiếu: <b>${esc(o.document_code)}</b> · Ngày tạo: ${date(o.created_on)}</p><p>Đối tác: ${esc(o.partners?.name||o.partner_name||'—')} · Kho: ${esc(warehouse(o.warehouse_id)?.name||'—')}</p><table><thead><tr><th>SKU</th><th>Hàng hóa</th><th>${inbound?'Dự kiến':'Yêu cầu'}</th><th>${inbound?'Thực nhận':'Đã xuất'}</th></tr></thead><tbody>${body}</tbody></table><p>Người lập: ${esc(o.created_by_profile?.full_name||'—')} · Trạng thái: ${esc(statusNames[o.status]||o.status)}</p><button onclick="window.print()">In phiếu</button></html>`);w.document.close();
}
function openDetail(id,kind){const s=state(), inbound=kind==='inbound',o=(inbound?s.inbounds:s.outbounds).find(x=>x.id===id);if(!o)return;
  const lines=inbound?o.inbound_order_lines:o.outbound_order_lines;
  const docs=inbound?s.documents.filter(d=>d.inbound_order_id===id):[];
  const docRows=docs.map(d=>'<div class="docrow"><span>'+esc(d.file_name)+' · '+Math.ceil(d.file_size/1024)+' KB</span><button class="row-action" data-action="open-document" data-id="'+esc(d.id)+'">Mở</button></div>').join('');
  const docsMarkup=inbound?'<div class="formsection">CHỨNG TỪ ĐÍNH KÈM</div>'+(docRows||'<div class="emptyhint">Chưa có chứng từ.</div>')+(canWarehouse()?'<div class="upload-row"><input type="file" data-inbound-file accept="application/pdf,image/jpeg,image/png,image/webp,application/vnd.openxmlformats-officedocument.wordprocessingml.document,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"><button class="btn" data-action="upload-inbound-document" data-id="'+esc(id)+'">Đính kèm tệp</button></div>':''):'';
  document.getElementById('modalTitle').textContent=`Chi tiết ${o.document_code}`;document.getElementById('modalDesc').textContent=`${statusNames[o.status]||o.status} · ${date(o.created_on)}`;
  document.getElementById('modalSaveDraft').hidden=true;document.getElementById('modalSubmit').textContent='Đóng';document.getElementById('modalSubmit').onclick=window.closeModal;
  document.getElementById('modalbody').innerHTML=`<div class="notice">${esc(o.partners?.name||o.partner_name||'—')} · ${esc(warehouse(o.warehouse_id)?.name||'—')}</div>${safeRows(['SKU','HÀNG HÓA',inbound?'DỰ KIẾN':'YÊU CẦU',inbound?'ĐÃ NHẬN':'ĐÃ XUẤT','VỊ TRÍ','SỐ LÔ'],lines.map(l=>({id:l.id,cells:[product(l.product_id)?.sku||'—',product(l.product_id)?.name||'—',qty(inbound?l.expected_quantity:l.requested_quantity),qty(inbound?l.received_quantity:l.issued_quantity),l.location_code||'—',l.lot_code||'—']})))}${docsMarkup}<button class="btn" data-print-order="${esc(id)}" data-print-kind="${kind}">In phiếu</button>`;
  window.MKWMS_MODAL_TYPE='';document.getElementById('modalback').classList.add('open');
}

async function handleAction(button){
  const name=button.dataset.action,id=button.dataset.id,client=db(),s=state();
  if(name==='new-inbound'||name==='new-outbound')return window.openModal(name==='new-inbound'?'Tạo phiếu nhập':'Tạo phiếu xuất','Nhập đầy đủ thông tin và các dòng hàng.',name==='new-inbound'?'inbound':'outbound');
  if(name==='new-product'||name==='edit-product')return editModal('product',s.products.find(x=>x.id===id));
  if(name==='new-partner'||name==='edit-partner')return editModal('partner',s.partners.find(x=>x.id===id));
  if(name==='partner-history')return openPartnerHistory(id);
  if(name==='new-warehouse'||name==='edit-warehouse')return editModal('warehouse',s.warehouses.find(x=>x.id===id));
  if(name==='new-transfer')return editModal('transfer');if(name==='new-adjustment')return editModal('adjustment');
  if(name==='edit-user')return editModal('user',s.profiles.find(x=>x.user_id===id));
  if(name==='order-detail')return openDetail(id,document.querySelector('.nav button.active')?.dataset.page||'inbound');
  if(name==='submit-inbound'||name==='approve-inbound'){
    const order=s.inbounds.find(o=>o.id===id);const rpc=name==='submit-inbound'?'submit_inbound_order':'approve_inbound_order';const {error}=await client.rpc(rpc,{target_order:id});if(error)return toast(error.message);await window.MKWMS_REFRESH();toast(name==='submit-inbound'?'Đã gửi phiếu nhập chờ duyệt.':'Đã duyệt phiếu nhập.');return;
  }
  if(name==='receive-inbound'){const order=s.inbounds.find(o=>o.id===id);if(order)openReceive(order);return;}
  if(name==='submit-outbound'){const {error}=await client.from('outbound_orders').update({status:'pending_approval'}).eq('id',id);if(error)return toast(error.message);await window.MKWMS_REFRESH();toast('Đã gửi phiếu xuất chờ duyệt.');return;}
  if(name==='approve-outbound'){const {error}=await client.rpc('approve_outbound_order',{target_order:id});if(error)return toast(error.message);await window.MKWMS_REFRESH();toast('Đã duyệt, giữ tồn và tự tạo lệnh giao nếu cần.');return;}
  if(name==='approve-adjustment'){const {error}=await client.rpc('approve_stock_adjustment',{target_adjustment:id});if(error)return toast(error.message);await window.MKWMS_REFRESH();toast('Đã duyệt và ghi sổ điều chỉnh tồn.');return;}
  if(name==='reverse-transaction'){
    const movement=s.movements.find(m=>m.source_id===id&&m.source_type!=='reversal');if(!movement)return;
    const reason=prompt('Nhập lý do đảo giao dịch (bắt buộc):');if(reason===null)return;if(!reason.trim())return toast('Cần nhập lý do đảo giao dịch.');
    const {error}=await client.rpc('reverse_inventory_transaction',{original_source_type:movement.source_type,original_source_id:id,reversal_reason:reason.trim()});if(error)return toast(error.message);await window.MKWMS_REFRESH();toast('Đã tạo giao dịch đảo và ghi nhật ký.');return;
  }
  if(name==='issue-outbound'){const order=s.outbounds.find(o=>o.id===id);if(order)openIssue(order);return;}
  if(name==='edit-delivery'){const d=s.deliveries.find(x=>x.id===id);if(d)editModal('delivery',d);return;}
  if(name==='upload-inbound-document'){
    const order=s.inbounds.find(x=>x.id===id),file=document.querySelector('[data-inbound-file]')?.files?.[0];if(!order||!file)return toast('Chọn chứng từ cần đính kèm.');
    await uploadOrderDocument(file,order.warehouse_id,order.id,'inbound');await window.MKWMS_REFRESH();openDetail(id,'inbound');toast('Đã lưu chứng từ đính kèm.');return;
  }
  if(name==='open-document'){
    const doc=s.documents.find(x=>x.id===id);if(!doc)return;const {data,error}=await client.storage.from('mkwms-documents').createSignedUrl(doc.storage_path,300);if(error)return toast(error.message);window.open(data.signedUrl,'_blank','noopener');return;
  }
  if(name==='retry-delivery'){const d=s.deliveries.find(x=>x.id===id);const dateInput=prompt('Ngày dự kiến giao lại (YYYY-MM-DD):',d?.expected_delivery_date||'');if(dateInput===null)return;const {error}=await client.rpc('create_delivery_retry',{target_delivery:id,new_expected_date:dateInput||null});if(error)return toast(error.message);await window.MKWMS_REFRESH();toast('Đã tạo lần giao tiếp theo.');return;}
  if(name==='toggle-product'||name==='toggle-partner'||name==='toggle-warehouse'){
    const collection=name==='toggle-product'?'products':name==='toggle-partner'?'partners':'warehouses';const row=s[collection].find(x=>x.id===id);if(!row)return;
    const {error}=await client.from(collection).update({active:!row.active,...(collection==='products'?{updated_by:s.user.id}:{})}).eq('id',id);if(error)return toast(error.message);await window.MKWMS_REFRESH();toast(row.active?'Đã ngừng hoạt động.':'Đã kích hoạt.');return;
  }
}
document.addEventListener('click',async e=>{
  const btn=e.target.closest('[data-action]');
  if(btn){
    if(btn.dataset.action.startsWith('export-')){try{await exportReport(btn.dataset.action)}catch(err){toast(err.message||'Không thể xuất Excel.')}return;}
    if(btn.dataset.action==='preview-opening'){await previewOpening();return;}
    if(btn.dataset.action==='download-opening-template'){try{await downloadOpeningTemplate()}catch(err){toast(err.message||'Không thể tạo file mẫu.')}return;}
    if(btn.dataset.action==='add-transfer-line'){document.querySelector('[data-transfer-lines]').insertAdjacentHTML('beforeend',transferLine());return;}
    if(btn.dataset.action==='add-adjust-line'){document.querySelector('[data-adjust-lines]').insertAdjacentHTML('beforeend',adjustLine());return;}
    try{await handleAction(btn)}catch(err){toast(err?.message||'Không thể hoàn tất thao tác.')}return;
  }
  const remove=e.target.closest('[data-remove-line]');if(remove){remove.closest('.ops-line').remove();return;}
  const print=e.target.closest('[data-print-order]');if(print){const inbound=print.dataset.printKind==='inbound',order=(inbound?state().inbounds:state().outbounds).find(o=>o.id===print.dataset.printOrder);if(order)printOrder(order,inbound);return;}
  const exportBtn=e.target.closest('[data-action^="export-"]');if(exportBtn){try{await exportReport(exportBtn.dataset.action)}catch(err){toast(err.message||'Không thể xuất Excel.')}return;}
  const opening=e.target.closest('[data-action="preview-opening"]');if(opening){await previewOpening();return;}
  const tpl=e.target.closest('[data-action="download-opening-template"]');if(tpl){await downloadOpeningTemplate();return;}
});
document.addEventListener('change',e=>{if(e.target.matches('[data-opening-file]'))document.querySelector('[data-opening-name]').textContent=e.target.files?.[0]?.name||'Chưa chọn tệp';});
document.addEventListener('input',e=>{if(e.target.matches('[data-filter-table]')){const q=e.target.value.toLocaleLowerCase();document.querySelectorAll('.data-table tbody tr').forEach(tr=>tr.style.display=tr.innerText.toLocaleLowerCase().includes(q)?'':'none');}});

async function exportWorkbook(name,sheets){
  const XLSX=await window.loadXlsxParser();const wb=XLSX.utils.book_new();for(const [title,rows] of sheets){XLSX.utils.book_append_sheet(wb,XLSX.utils.aoa_to_sheet(rows),title.slice(0,31));}XLSX.writeFile(wb,name);
}
async function exportReport(which){
  const s=state(), products=new Map(s.products.map(p=>[p.id,p])), warehouses=new Map(s.warehouses.map(w=>[w.id,w]));
  const from=document.querySelector('[name="report_from"]')?.value||'',to=document.querySelector('[name="report_to"]')?.value||'',wh=document.querySelector('[name="report_warehouse"]')?.value||'',sku=document.querySelector('[name="report_product"]')?.value||'';
  const inScope=(warehouseId,productId,createdAt)=>((!wh||wh===warehouseId)&&(!sku||sku===productId)&&(!from||createdAt?.slice(0,10)>=from)&&(!to||createdAt?.slice(0,10)<=to));
  const balances=[['Kho','SKU','Tên hàng','Vị trí','Số lô','Tồn thực tế','Đã giữ','Khả dụng','Tồn tối thiểu'],...(s.balances||[]).filter(b=>(!wh||wh===b.warehouse_id)&&(!sku||sku===b.product_id)).map(b=>{const p=products.get(b.product_id),w=warehouses.get(b.warehouse_id);return [w?.name||'',p?.sku||'',p?.name||'',b.location_code,b.lot_code,b.on_hand_quantity,b.reserved_quantity,b.available_quantity,p?.minimum_stock||0]})];
  const movements=(s.movements||[]).filter(m=>inScope(m.warehouse_id,m.product_id,m.created_at));
  const ledger=[['Thời gian','Loại giao dịch','SKU','Kho','SL tăng/giảm','Nguồn','Vị trí','Lô'],...movements.map(m=>[datetime(m.created_at),m.movement_type,products.get(m.product_id)?.sku||'',warehouses.get(m.warehouse_id)?.name||'',m.quantity_delta,m.source_type,m.location_code,m.lot_code])];
  const low=[['SKU','Tên hàng','Định mức','Tồn'],...s.products.filter(p=>(!sku||sku===p.id)&&p.active).filter(p=>{const n=s.balances.filter(b=>b.product_id===p.id&&(!wh||wh===b.warehouse_id)).reduce((a,b)=>a+Number(b.on_hand_quantity),0);return n<p.minimum_stock}).map(p=>[p.sku,p.name,p.minimum_stock,s.balances.filter(b=>b.product_id===p.id&&(!wh||wh===b.warehouse_id)).reduce((a,b)=>a+Number(b.on_hand_quantity),0)])];
  const cutoff=new Date();cutoff.setDate(cutoff.getDate()-90);const movements90=(s.movements||[]).filter(m=>(!wh||wh===m.warehouse_id)&&(!sku||sku===m.product_id)&&new Date(m.created_at)>=cutoff);const slow=[['SKU','Tên hàng','Tồn hiện tại','Số giao dịch 90 ngày'],...s.products.filter(p=>(!sku||sku===p.id)&&p.active).filter(p=>!movements90.some(m=>m.product_id===p.id)).map(p=>[p.sku,p.name,s.balances.filter(b=>b.product_id===p.id&&(!wh||wh===b.warehouse_id)).reduce((a,b)=>a+Number(b.on_hand_quantity),0),0])];
  const deliveries=[['Mã giao','Phiếu xuất','Ngày dự kiến','Trạng thái','Đơn vị vận chuyển','Tài xế','Người nhận','Thời gian giao','Số lượng yêu cầu','Số lượng đã giao'],...s.deliveries.filter(d=>{const o=s.outbounds.find(x=>x.id===d.outbound_order_id);return (!wh||wh===o?.warehouse_id)&&(!sku||o?.outbound_order_lines?.some(l=>l.product_id===sku))&&(!from||d.created_at?.slice(0,10)>=from)&&(!to||d.created_at?.slice(0,10)<=to)}).map(d=>{const o=s.outbounds.find(x=>x.id===d.outbound_order_id),requested=(o?.outbound_order_lines||[]).filter(l=>!sku||sku===l.product_id).reduce((n,l)=>n+Number(l.requested_quantity),0),received=(s.deliveryLines||[]).filter(l=>l.delivery_order_id===d.id&&(!sku||o?.outbound_order_lines?.some(x=>x.id===l.outbound_order_line_id&&x.product_id===sku))).reduce((n,l)=>n+Number(l.quantity_delivered),0);return [d.delivery_code,o?.document_code||'',d.expected_delivery_date||'',statusNames[d.status]||d.status,d.carrier_name,d.driver_name,d.received_by,d.actual_delivery_at||'',requested,received]})];
  const map={'export-stock':[['Nhap-xuat-ton',balances]],'export-ledger':[['The-kho',ledger]],'export-low':[['Duoi-dinh-muc',low]],'export-slow':[['Cham-luan-chuyen',slow]],'export-deliveries':[['Giao-hang',deliveries]],'export-all-reports':[['Nhap-xuat-ton',balances],['The-kho',ledger],['Duoi-dinh-muc',low],['Cham-luan-chuyen',slow],['Giao-hang',deliveries]]};
  await exportWorkbook(`MKWMS_${which.replace('export-','')}_${new Date().toISOString().slice(0,10)}.xlsx`,map[which]);
}

async function downloadOpeningTemplate(){
  const XLSX=await window.loadXlsxParser(),wb=XLSX.utils.book_new(),p=state().products.find(x=>x.active),w=state().warehouses.find(x=>x.active);XLSX.utils.book_append_sheet(wb,XLSX.utils.aoa_to_sheet([['SKU','MaKho','ViTri','SoLo','SoLuong'],...(p&&w?[[p.sku,w.code,'','',1]]:[])]),'Ton dau ky');XLSX.writeFile(wb,'MKWMS_mau_ton_dau_ky.xlsx');
}
let openingRows=[];
async function previewOpening(){
  const status=document.querySelector('[data-opening-status]'),preview=document.querySelector('[data-opening-preview]'),file=document.querySelector('[data-opening-file]')?.files?.[0];
  if(!file){status.textContent='Chọn file Excel trước.';status.className='import-status error';return;}
  try{
    const XLSX=await window.loadXlsxParser(),wb=XLSX.read(await file.arrayBuffer(),{cellDates:false}),sheet=wb.Sheets['Ton dau ky'];if(!sheet)throw new Error('Không có sheet Ton dau ky.');
    const matrix=XLSX.utils.sheet_to_json(sheet,{header:1,raw:true,defval:''});const headers=['SKU','MaKho','ViTri','SoLo','SoLuong'];if(headers.some((h,i)=>matrix[0]?.[i]!==h))throw new Error('Tiêu đề cột không đúng mẫu tồn đầu kỳ.');
    const seen=new Set(),rows=[];for(let i=1;i<matrix.length;i++){const [sku,code,location,lot,quantity]=matrix[i];if([sku,code,location,lot,quantity].every(v=>String(v??'').trim()===''))continue;const errors=[];const productRow=state().products.find(p=>p.sku.toLocaleLowerCase()===String(sku).trim().toLocaleLowerCase()),w=state().warehouses.find(x=>x.code.toLocaleLowerCase()===String(code).trim().toLocaleLowerCase());const k=`${sku}|${code}|${location}|${lot}`.toLowerCase();if(!productRow)errors.push('SKU không tồn tại');if(!w)errors.push('Mã kho không tồn tại');if(!Number.isInteger(Number(quantity))||Number(quantity)<=0)errors.push('Số lượng phải là số nguyên dương');if(seen.has(k))errors.push('Dòng bị trùng');seen.add(k);const existing=state().balances.find(b=>b.product_id===productRow?.id&&b.warehouse_id===w?.id&&(b.location_code||'')===String(location||'').trim()&&(b.lot_code||'')===String(lot||'').trim());if(existing)errors.push('Ô tồn này đã tồn tại; không ghi đè');rows.push({row:i+1,sku:String(sku),warehouse:w,product:productRow,location:String(location||'').trim(),lot:String(lot||'').trim(),quantity:Number(quantity),errors});}
    if(!rows.length)throw new Error('File không có dòng tồn đầu kỳ.');openingRows=rows;const invalid=rows.filter(r=>r.errors.length).length;preview.innerHTML=`<div class="import-summary"><span class="pill">${rows.length} dòng</span><span class="pill ${invalid?'invalid':'valid'}">${invalid?`${invalid} lỗi`:'Hợp lệ'}</span></div><div class="tablewrap"><table class="table"><thead><tr><th>DÒNG</th><th>SKU</th><th>KHO</th><th>VỊ TRÍ</th><th>LÔ</th><th>SỐ LƯỢNG</th><th>LỖI</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${r.row}</td><td>${esc(r.sku)}</td><td>${esc(r.warehouse?.name||'')}</td><td>${esc(r.location)}</td><td>${esc(r.lot)}</td><td>${qty(r.quantity)}</td><td>${esc(r.errors.join('; ')||'—')}</td></tr>`).join('')}</tbody></table></div><button class="btn primary" data-action="confirm-opening" ${invalid?'disabled':''}>Xác nhận nhập tồn đầu kỳ</button>`;status.textContent=invalid?'Sửa lỗi trong file rồi chọn lại.':'Kiểm tra thành công; bấm xác nhận để ghi dữ liệu.';status.className=`import-status ${invalid?'error':'success'}`;
  }catch(error){status.textContent=error.message;status.className='import-status error';preview.innerHTML='';openingRows=[];}
}
document.addEventListener('click',async e=>{
  const b=e.target.closest('[data-action="confirm-opening"]');if(!b)return;
  try{
    const client=db(),payload=openingRows.map(r=>({sku:r.sku,warehouse_code:r.warehouse.code,location_code:r.location,lot_code:r.lot,quantity:r.quantity}));
    const {error}=await client.rpc('import_opening_balances',{idempotency_key:crypto.randomUUID(),opening_rows:payload});if(error)throw error;
    openingRows=[];await window.MKWMS_REFRESH();document.querySelector('[data-opening-status]').textContent='Đã nhập tồn đầu kỳ.';document.querySelector('[data-opening-status]').className='import-status success';document.querySelector('[data-opening-preview]').innerHTML='';toast('Đã cập nhật tồn đầu kỳ.');
  }catch(error){toast(error.message||'Không thể nhập tồn đầu kỳ.');}
});

document.head.insertAdjacentHTML('beforeend',`<style>
.lineitem{grid-template-columns:minmax(210px,2fr) 90px minmax(110px,1fr) minmax(110px,1fr) 32px!important}.ops-line{display:grid;grid-template-columns:minmax(180px,2fr) repeat(3,minmax(90px,1fr));gap:8px;align-items:end;margin:8px 0;padding:9px;border:1px solid #edf0f5;border-radius:8px}.ops-line small{display:block;color:#8290a3;margin-top:4px}.check-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;margin-top:7px}.check-option{display:flex;gap:8px;align-items:center;border:1px solid #e6ebf2;border-radius:7px;padding:9px;font-size:11px}.check-option input{width:auto}.report-card{padding:16px}.report-card .panelhead{padding:0 0 14px}.report-card h2{font-size:14px}.report-card p{font-size:11px;color:#7b8798}.docrow{display:flex;justify-content:space-between;gap:10px;align-items:center;padding:8px 0;border-bottom:1px solid var(--line);font-size:12px}.remove{height:36px;border:1px solid var(--line);border-radius:7px;background:#fff;color:#a0aaba;font-size:16px}.emptyhint{padding:25px;text-align:center;color:#8491a4}@media(max-width:760px){.lineitem{grid-template-columns:1fr 80px!important}.lineitem .field:nth-child(3),.lineitem .field:nth-child(4){grid-column:auto}.ops-line{grid-template-columns:1fr 1fr}.ops-line>div:first-child{grid-column:1/-1}.check-grid{grid-template-columns:1fr}}
</style>`);
