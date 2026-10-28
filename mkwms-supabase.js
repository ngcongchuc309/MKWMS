import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const config = window.MKWMS_CONFIG;
const supabase = createClient(config.supabaseUrl, config.supabasePublishableKey, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});
window.mkwmsDb = supabase;

const form = document.getElementById('mkwmsLogin');
const errorBox = document.getElementById('authError');
const submitButton = form.querySelector('button[type="submit"]');

function showError(message) {
  errorBox.textContent = message;
}

async function loadWorkspace(user) {
  showError('');
  const { data: profile, error: profileError } = await supabase
    .from('profiles').select('user_id,full_name,role,active').eq('user_id', user.id).maybeSingle();
  if (profileError) throw profileError;
  if (!profile || !profile.active) {
    showError('Tài khoản chưa được quản trị viên cấp vai trò trong MKWMS. Hãy liên hệ quản trị viên để kích hoạt.');
    return;
  }

  const [warehouseResult, productResult, balanceResult, partnerResult, inboundResult, outboundResult, deliveryResult, deliveryLineResult, movementResult, adjustmentResult, transferResult, profileResult, scopeResult, auditResult, documentResult] = await Promise.all([
    supabase.from('warehouses').select('id,code,name,address,active').eq('active', true).order('name'),
    supabase.from('products').select('id,sku,name,category,brand,unit,package_spec,minimum_stock,active').order('sku'),
    supabase.from('stock_balances').select('warehouse_id,product_id,location_code,lot_code,on_hand_quantity,reserved_quantity,available_quantity,updated_at'),
    supabase.from('partners').select('id,partner_code,partner_type,name,tax_code,address,contact_name,phone,email,active').order('name'),
    supabase.from('inbound_orders').select('id,document_code,inbound_type,supplier_id,status,created_on,delivery_on,receiver_name,receiver_phone,warehouse_id,created_by,created_at,created_by_profile:profiles!inbound_orders_created_by_fkey(full_name),partners(name),inbound_order_lines(id,product_id,expected_quantity,received_quantity,location_code,lot_code,products(sku,name,unit))').order('created_at', { ascending: false }),
    supabase.from('outbound_orders').select('id,document_code,outbound_type,partner_id,partner_name,status,created_on,expected_delivery_date,receiver_name,receiver_phone,delivery_address,warehouse_id,created_by,created_at,created_by_profile:profiles!outbound_orders_created_by_fkey(full_name),partners(name),outbound_order_lines(id,product_id,requested_quantity,reserved_quantity,issued_quantity,location_code,lot_code,products(sku,name,unit))').order('created_at', { ascending: false }),
    supabase.from('delivery_orders').select('id,delivery_code,outbound_order_id,delivery_sequence,status,expected_delivery_date,receiver_name,receiver_phone,delivery_address,carrier_name,driver_name,driver_phone,vehicle_plate,actual_delivery_at,received_by,proof_path,updated_at,created_at,outbound_orders(document_code,warehouse_id)').order('created_at', { ascending: false }),
    supabase.from('delivery_order_lines').select('delivery_order_id,outbound_order_line_id,quantity_delivered'),
    supabase.from('inventory_movements').select('id,warehouse_id,product_id,movement_type,quantity_delta,source_type,source_id,location_code,lot_code,created_by,created_at').order('created_at',{ascending:false}).limit(1000),
    supabase.from('stock_adjustments').select('id,document_code,warehouse_id,reason,status,created_by,approved_by,created_at,approved_at,posted_at,stock_adjustment_lines(id,product_id,location_code,lot_code,counted_quantity,system_quantity,quantity_delta)').order('created_at',{ascending:false}),
    supabase.from('stock_transfers').select('id,document_code,from_warehouse_id,to_warehouse_id,status,created_by,created_at,stock_transfer_lines(id,product_id,quantity,from_location_code,from_lot_code,to_location_code,to_lot_code)').order('created_at',{ascending:false}),
    supabase.from('profiles').select('user_id,email,full_name,role,active,created_at').order('full_name'),
    supabase.from('user_warehouses').select('user_id,warehouse_id'),
    supabase.from('audit_log').select('id,actor_id,action,entity_type,entity_id,details,created_at,actor:profiles(full_name)').order('created_at',{ascending:false}).limit(200),
    supabase.from('order_documents').select('id,warehouse_id,inbound_order_id,delivery_order_id,file_name,storage_path,mime_type,file_size,uploaded_by,created_at').order('created_at',{ascending:false}),
  ]);

  for (const result of [warehouseResult, productResult, balanceResult, partnerResult, inboundResult, outboundResult, deliveryResult, deliveryLineResult, movementResult, adjustmentResult, transferResult, profileResult, scopeResult, auditResult, documentResult]) {
    if (result.error) throw result.error;
  }

  const movements = [...(movementResult.data || [])];
  for (let offset = movements.length; movements.length && movements.length % 1000 === 0; offset += 1000) {
    const { data, error } = await supabase.from('inventory_movements')
      .select('id,warehouse_id,product_id,movement_type,quantity_delta,source_type,source_id,location_code,lot_code,created_by,created_at')
      .order('created_at', { ascending: false }).range(offset, offset + 999);
    if (error) throw error;
    movements.push(...(data || []));
    if ((data || []).length < 1000) break;
  }

  window.MKWMS_OUTBOUND_IDS = Object.fromEntries((outboundResult.data || []).map(row => [row.document_code, row.id]));
  window.MKWMS_INBOUND_IDS = Object.fromEntries((inboundResult.data || []).map(row => [row.document_code, row.id]));
  window.MKWMS_DELIVERY_IDS = Object.fromEntries((deliveryResult.data || []).map(row => [row.delivery_code, row.id]));

  const workspace = {
    profile, user,
    warehouses: warehouseResult.data || [], products: productResult.data || [],
    balances: balanceResult.data || [], partners: partnerResult.data || [],
    inbounds: inboundResult.data || [], outbounds: outboundResult.data || [],
    deliveries: deliveryResult.data || [], deliveryLines: deliveryLineResult.data || [],
    movements, adjustments: adjustmentResult.data || [],
    transfers: transferResult.data || [], profiles: profileResult.data || [],
    userWarehouses: scopeResult.data || [], audit: auditResult.data || [], documents: documentResult.data || [],
  };
  window.MKWMS_DB = supabase;
  window.MKWMS_REFRESH = () => loadWorkspace(user);
  window.MKWMS_STATE = workspace;
  window.mkwmsLoadData({
    ...workspace,
  });
  window.dispatchEvent(new CustomEvent('mkwms:workspace-loaded', { detail: workspace }));
  window.mkwmsConfirmProductImport = async () => {
    const invalid = window.importPreviewRows?.filter(row => row.errors.length) || [];
    if (invalid.length || !window.importPreviewRows?.length) {
      showError('Hãy sửa lỗi và kiểm tra lại file trước khi nhập.');
      return;
    }
    const items = window.importPreviewRows.map(row => row.cells);
    const rows = items.map(item => ({
      sku: item.SKU,
      name: item.TenHang,
      category: item.NhomHang || '',
      brand: item.ThuongHieu || '',
      unit: item.DonViTinh,
      package_spec: item.QuyCachDongGoi || '',
      minimum_stock: Number(item.TonToiThieu || 0),
      active: item.TrangThai === 'Hoạt động',
      created_by: user.id,
      updated_by: user.id,
    }));
    const { error } = await supabase.from('products').insert(rows);
    if (error) {
      const msg = error.code === '23505' ? 'SKU vừa được thêm bởi người dùng khác. Hãy tải lại dữ liệu và kiểm tra SKU trùng.' : error.message;
      document.getElementById('importStatus').textContent = msg;
      document.getElementById('importStatus').className = 'import-status error';
      return;
    }
    document.getElementById('importStatus').textContent = `Đã ghi ${rows.length} mặt hàng vào Supabase.`;
    document.getElementById('importStatus').className = 'import-status success';
    await loadWorkspace(user);
  };
  window.mkwmsLogout = async () => { await supabase.auth.signOut(); window.location.reload(); };
  window.mkwmsCreateOrder = async (kind, values, lines, action) => {
    const warehouseId = String(values.get('warehouse') || '');
    const createdOn = String(values.get('createdDate') || new Date().toISOString().slice(0, 10));
    const code = String(values.get('voucherCode') || '').trim() || window.nextRef(kind === 'inbound' ? 'PN' : 'PX', window.MKWMS_PAGES[kind].rows);
    let partnerId = null;
    let partnerName = '';
    if (kind === 'inbound') {
      partnerName = String(values.get('supplier') || '').trim();
      const inboundKind = values.get('inboundType') || 'Nhập nhà cung cấp';
      const partnerKind = inboundKind === 'Nhập trả hàng' ? 'customer' : 'supplier';
      let partner = (window.MKWMS_PARTNERS || []).find(p => p.name.toLocaleLowerCase() === partnerName.toLocaleLowerCase() && [partnerKind,'both'].includes(p.partner_type));
      if (!partner) {
        const { data, error } = await supabase.from('partners').insert({
          partner_code: `${partnerKind === 'customer' ? 'KH' : 'NCC'}-${Date.now().toString().slice(-10)}`, partner_type: partnerKind, name: partnerName,
        }).select('id,name,partner_code,partner_type,active').single();
        if (error) throw error;
        partner = data;
        window.MKWMS_PARTNERS.push(partner);
      }
      partnerId = partner.id;
    } else {
      partnerName = String(values.get('partner') || '').trim();
      if (values.get('outboundType') === 'Xuất bán') {
        let partner = (window.MKWMS_PARTNERS || []).find(p => p.name.toLocaleLowerCase() === partnerName.toLocaleLowerCase() && ['customer','both'].includes(p.partner_type));
        if (!partner) {
          const { data, error } = await supabase.from('partners').insert({
            partner_code: `KH-${Date.now().toString().slice(-10)}`, partner_type: 'customer', name: partnerName,
          }).select('id,name,partner_code,partner_type,active').single();
          if (error) throw error;
          partner = data;
          window.MKWMS_PARTNERS.push(partner);
        }
        partnerId = partner.id;
      }
    }
    const outbound = kind === 'outbound';
    const header = outbound ? {
      document_code: code,
      outbound_type: ({'Xuất bán':'sale','Xuất nội bộ':'internal','Xuất khác':'other'})[values.get('outboundType')] || 'sale',
      partner_id: partnerId,
      partner_name: partnerName,
      warehouse_id: warehouseId,
      shipping_method: values.get('shippingMethod') === 'Khách tự nhận' ? 'pickup' : 'delivery',
      expected_delivery_date: values.get('shippingMethod') === 'Giao hàng' ? values.get('deliveryDate') : null,
      receiver_name: values.get('shippingMethod') === 'Giao hàng' ? values.get('receiverName') : '',
      receiver_phone: values.get('shippingMethod') === 'Giao hàng' ? values.get('receiverPhone') : '',
      delivery_address: values.get('shippingMethod') === 'Giao hàng' ? values.get('address') : '',
      status: action === 'draft' ? 'draft' : 'pending_approval',
      created_on: createdOn,
      created_by: user.id,
    } : {
      document_code: code,
      inbound_type: ({'Nhập nhà cung cấp':'supplier','Nhập trả hàng':'return','Nhập khác':'other'})[values.get('inboundType')] || 'supplier',
      supplier_id: partnerId,
      warehouse_id: warehouseId,
      status: 'draft',
      created_on: createdOn,
      delivery_on: values.get('deliveryDate') || null,
      receiver_name: String(values.get('receiverName') || '').trim(),
      receiver_phone: String(values.get('receiverPhone') || '').trim(),
      created_by: user.id,
    };
    const table = outbound ? 'outbound_orders' : 'inbound_orders';
    const { data: order, error } = await supabase.from(table).insert(header).select('id,document_code').single();
    if (error) throw error;
    const detailRows = lines.map(line => outbound ? {
      outbound_order_id: order.id, product_id: line.productId, requested_quantity: line.quantity, location_code: line.locationCode || '', lot_code: line.lotCode || '',
    } : {
      inbound_order_id: order.id, product_id: line.productId, expected_quantity: line.quantity, location_code: line.locationCode || '', lot_code: line.lotCode || '',
    });
    const { error: lineError } = await supabase.from(outbound ? 'outbound_order_lines' : 'inbound_order_lines').insert(detailRows);
    if (lineError) throw new Error(`Phiếu ${code} đã lưu nhưng chi tiết chưa lưu: ${lineError.message}`);
    await loadWorkspace(user);
    return code;
  };
  window.MKWMS_SAVE_ORDER_MODAL = async (action = 'save') => {
    const formElement = document.getElementById('recordForm');
    if (!formElement || !formElement.reportValidity()) return;
    if (!['inbound','outbound'].includes(window.MKWMS_MODAL_TYPE)) {
      window.toast('Màn hình này chưa được nối với cơ sở dữ liệu.');
      return;
    }
    const values = new FormData(formElement);
    const lines = [...formElement.querySelectorAll('.lineitem')].map(line => ({
      productId: line.querySelector('select').value,
      quantity: Number(line.querySelector('input').value),
      locationCode: line.querySelector('[name="locationCode"]')?.value.trim() || '',
      lotCode: line.querySelector('[name="lotCode"]')?.value.trim() || '',
    }));
    if (lines.some(line => !line.productId || !Number.isInteger(line.quantity) || line.quantity <= 0)) {
      window.toast('Chọn hàng hóa và số lượng hợp lệ cho từng dòng.');
      return;
    }
    try {
      const kind = window.MKWMS_MODAL_TYPE;
      const code = await window.mkwmsCreateOrder(kind, values, lines, action);
      if (kind === 'inbound' && action !== 'draft') {
        const { error } = await supabase.rpc('submit_inbound_order', { target_order: window.MKWMS_INBOUND_IDS[code] });
        if (error) throw error;
        await loadWorkspace(user);
      }
      window.closeModal();
      window.navigate(kind);
      window.toast(`Đã lưu phiếu ${code} vào Supabase.`);
    } catch (err) {
      window.toast(err?.message || 'Không thể lưu phiếu.');
    }
  };
  window.saveModal = window.MKWMS_SAVE_ORDER_MODAL;
  window.outboundAction = row => {
    const code = window.escapeHtml(row[0]);
    if (row[7] === 'Bản nháp') return `<button class="row-action" onclick="mkwmsSubmitOutbound('${code}')">Gửi duyệt</button>`;
    if (row[7] === 'Chờ duyệt') return `<button class="row-action approve" onclick="mkwmsApproveOutbound('${code}')">Duyệt phiếu</button>`;
    if (row[7] === 'Đã duyệt' && window.MKWMS_OUTBOUND_IDS[row[0]]) return `<button class="row-action" onclick="navigate('delivery')">Xem lệnh giao</button>`;
    return '—';
  };
  window.mkwmsSubmitOutbound = async code => {
    const id = window.MKWMS_OUTBOUND_IDS[code];
    const { error } = await supabase.from('outbound_orders').update({ status: 'pending_approval' }).eq('id', id);
    if (error) return window.toast(error.message);
    await loadWorkspace(user); window.navigate('outbound'); window.toast(`Phiếu ${code} đã gửi duyệt.`);
  };
  window.mkwmsApproveOutbound = async code => {
    const id = window.MKWMS_OUTBOUND_IDS[code];
    const { error } = await supabase.rpc('approve_outbound_order', { target_order: id });
    if (error) return window.toast(error.message);
    await loadWorkspace(user); window.navigate('outbound'); window.toast(`Đã duyệt phiếu ${code} và xử lý lệnh giao.`);
  };
  window.updateDeliveryDate = async (code, value) => {
    const id = window.MKWMS_DELIVERY_IDS[code];
    const { error } = await supabase.from('delivery_orders').update({ expected_delivery_date: value }).eq('id', id);
    if (error) return window.toast(error.message);
    await loadWorkspace(user); window.navigate('delivery'); window.toast(`Đã cập nhật ngày giao của ${code}.`);
  };
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!form.reportValidity()) return;
  submitButton.disabled = true;
  submitButton.textContent = 'Đang đăng nhập…';
  showError('');
  const values = new FormData(form);
  const { data, error } = await supabase.auth.signInWithPassword({
    email: String(values.get('email')).trim(),
    password: String(values.get('password')),
  });
  try {
    if (error) throw error;
    await loadWorkspace(data.user);
  } catch (err) {
    showError(err?.message || 'Không thể tải dữ liệu MKWMS. Vui lòng thử lại.');
  } finally {
    submitButton.disabled = false;
    submitButton.textContent = 'Đăng nhập';
  }
});

const { data: { session } } = await supabase.auth.getSession();
if (session?.user) {
  try { await loadWorkspace(session.user); }
  catch (err) { showError(err?.message || 'Không thể tải dữ liệu MKWMS.'); }
}

supabase.auth.onAuthStateChange((event, session) => {
  if (event === 'SIGNED_OUT') document.body.classList.remove('authenticated');
  if (event === 'SIGNED_IN' && session?.user && !document.body.classList.contains('authenticated')) {
    queueMicrotask(() => loadWorkspace(session.user).catch(err => showError(err?.message || 'Không thể tải dữ liệu MKWMS.')));
  }
});
