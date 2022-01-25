import { Principal } from "@dfinity/principal";
import qrcode from "./qrcode";
import { Agent, decodeIdentity } from "./agent";

const MIN_ALLOCATION = 0.001; // in trillion cycles

function formatICP(e8s) {
  return (Number((BigInt(e8s) * 10000n) / 100000000n) / 10000).toFixed(4);
}

function formatCycle(val, d = 3) {
  return (Number((BigInt(val) * 1000n) / 1000000000000n) / 1000).toFixed(d);
}

function formatAlias(allocation) {
  let id = allocation.canister.id.toString();
  let len = id.length + allocation.alias ? allocation.alias.length + 1 : 0;
  let name = allocation.alias
    ? `${allocation.alias} <span class='grayedout'>${id}</span>`
    : id;
  return len < 40 ? name : name.substring(0, 40) + "..";
}

var agent = null;

BigInt.prototype.toJSON = function () {
  return Number(this);
};

function find_canister_allocation(canister_id) {
  let user_info = agent.get_user_info();
  if (user_info) {
    let allocations = user_info.allocations;
    for (var i = 0; i < allocations.length; i++) {
      let allocation = allocations[i];
      if (canister_id.toString() == allocation.canister.id.toString()) {
        return allocation;
      }
    }
  }
}

function refresh_stats() {
  agent.tipjar_stats().then((stats) => {
    document.getElementById("stats").innerText = `${Number(
      stats.donors
    )} Donors ♡ ${Number(stats.canisters)} Canisters ♡ ${formatCycle(
      stats.donated,
      1
    )} of ${formatCycle(
      stats.funded + stats.donated,
      1
    )} Trillion Cycles Donated`;
  });
}

var last_account_id;
function show_account_id() {
  document.getElementById("account_id_copier").hidden = false;
  document.getElementById("account_id_spinner").hidden = true;
  let account_id = agent.account_id_hex();
  if (account_id != last_account_id) {
    last_account_id = account_id;
    document.getElementById("account_id").value = account_id;
    let typeNumber = 0;
    let errorCorrectionLevel = "L";
    let qr = qrcode(typeNumber, errorCorrectionLevel);
    qr.addData(account_id.toUpperCase(), "Alphanumeric");
    qr.make();
    let node = document.getElementById("account_qrcode");
    let img = document.createElement("div");
    img.innerHTML = qr.createImgTag(3, 3);
    node.replaceChild(img, node.children[0]);
  }
}

function hide_account() {
  document.getElementById("account_id_copier").hidden = true;
  document.getElementById("account_id_spinner").hidden = false;
  document.getElementById("account_id").value = "";
  document.getElementById("icp_balance").value = "";
  document.getElementById("cycle_balance").value = "";
  let qr_div = document.getElementById("account_qrcode").children;
  if (qr_div.length > 0 && qr_div[0].attr && ar_div[0].attr("src")) {
    qr_div[0].hidden = true;
  }
  if (refresh_interval) {
    clearInterval(refresh_interval);
    refresh_interval = null;
  }
}

function show_account_balance(info) {
  document.getElementById("icp_balance").value = formatICP(
    info.balance.icp.e8s
  );
  let spinner = document.getElementById("cycle_balance_spinner");
  let error = document.getElementById("banner_error");
  document.getElementById("cycle_balance").value =
    formatCycle(info.balance.cycle) + "T";
  spinner.hidden = true;
  if (info.status && info.status.length > 0) {
    let s = info.status[0];
    if ("DepositingCycle" in s) {
      error.innerText = "";
      spinner.hidden = false;
    } else if ("DepositError" in s) {
      if (spinner.hidden == false) {
        error.innerText = s.DepositError;
      }
    }
  }
  if (
    spinner.hidden &&
    error.innerText == "" &&
    info.balance.cycle > 0 &&
    !agent.is_authenticated()
  ) {
    error.innerHTML =
      "<br>Please <a id='login_reminder'>login</a> to claim the cycle balance to your account.<br><small class='grayedout'>Unclaimed cycles will be forfeited (donated to TipJar itself) after 30 days.</small>";
  }
}

function toUTC(timestamp) {
  let date = new Date(Number(timestamp / 1000000n));
  return date.toUTCString();
}

function toDays(period) {
  return Number(period / 1000000000n / 3600n / 24n);
}

function canister_summary(allocation) {
  let canister = allocation.canister;
  console.log(canister);
  var estimation = ".";
  if (canister.usage.length > 3) {
    var usage = 0n;
    var period = 0n;
    for (var i = 0; i < canister.usage.length; i++) {
      usage += canister.usage[i].cycle;
      period += canister.usage[i].period;
    }
    period = period / 3600000000000n;
    if (period > 0) {
      let hourly = usage / period;
      if (hourly > 0) {
        let days = canister.total_allocation / hourly / 24n;
        estimation = `, estimated to last for another ${Number(
          days
        )} days.</p>`;
      }
    }
  }
  var donations = "It has yet to receive (or need) the first donation.";
  if (canister.total_donated > 0) {
    var percent = String((allocation.donated * 100n) / canister.total_donated);
    if (percent < 1) {
      percent = "less than 1";
    }
    let days = toDays(canister.last_checked - canister.first_checked);
    let since =
      days == 0 ? "" : ` since ${days} day` + (days == 1 ? "" : "s") + " ago";
    donations = `You have donated ${formatCycle(
      allocation.donated
    )}T, about ${percent}% of the total contribution it has received${since}.`;
  }
  return [
    `<p class="grayedout">This canister had ${formatCycle(
      canister.last_checked_balance
    )}T cycles, last checked on ${toUTC(canister.last_checked)}.`,
    donations,
    `Currently it has a total allocation of ${formatCycle(
      canister.total_allocation
    )}T from all donors` + estimation,
  ].join("<br/>");
}

function canister_row(allocation) {
  let id = allocation.canister.id.toString();
  return [
    `<td><a id='anchor_${id}'>${formatAlias(
      allocation
    )}<span class="max"><i class="far fa-edit"></i></span></a></td>`,
    `<td class='right'>${formatCycle(allocation.allocated)}T</td>`,
    `<td class='right'>${formatCycle(allocation.donated)}T</td>`,
  ].join("");
}

async function save_canister(tr, id, allocation) {
  let save_btn = document.getElementById(`save_canister_${id}`);
  save_btn.blur();
  let cancel_btn = document.getElementById(`cancel_canister_${id}`);
  let error_p = document.getElementById(`save_canister_error_${id}`);
  let alias_input = document.getElementById(`alias_${id}`);
  let allocated_input = document.getElementById(`allocated_${id}`);
  let alias_spinner = document.getElementById(`alias_${id}_spinner`);
  let allocated_spinner = document.getElementById(`allocated_${id}_spinner`);
  let alias = alias_input.value.trim();
  let allocated_str = allocated_input.value.trim().replace("T", "");
  error_p.innerText = "";
  if (isNaN(allocated_str)) {
    error_p.innerText = "Please input a valid allocation value (decimal).";
    return;
  }
  let allocated = BigInt(allocated_str * 1e12);
  if (alias != allocation.alias) {
    alias_spinner.hidden = false;
  }
  if (allocated != allocation.allocated) {
    allocated_spinner.hidden = false;
  }
  if (alias_spinner.hidden && allocated_spinner.hidden) {
    error_p.innerText = "Please make a change before saving.";
    return;
  }
  save_btn.disabled = true;
  cancel_btn.disabled = true;
  try {
    let result = await agent.tipjar_allocate({
      canister: allocation.canister.id,
      alias: alias == "" ? [] : [alias],
      allocated,
    });
    console.log(result);
    if (result.ok) {
      update_user_info(result.ok);
      let new_allocation = find_canister_allocation(allocation.canister.id);
      tr.innerHTML = canister_row(new_allocation);
      document.getElementById("anchor_" + id).onclick = () => {
        show_canister_by_id(id);
      };
      refresh_stats();
      show_account_balance(result.ok);
    } else {
      let err = result.err;
      if ("UserDoesNotExist" in err) {
      } else if ("CanisterStatusError" in err) {
        error_p.innerHTML = explain_canister_status_error(
          err.CanisterStatusError
        );
      } else if ("InsufficientBalance" in err) {
        error_p.innerText = `You only have a balance of ${formatCycle(
          err.InsufficientBalance
        )}T, not enough to make this allocation.`;
        document.getElementById(`allocated_${id}`).focus();
      } else if ("AliasTooShort" in err) {
        error_p.innerText = `The alias must have at least ${err.AliasTooShort} characters.`;
        document.getElementById(`alias_${id}`).focus();
      } else if ("AliasTooLong" in err) {
        error_p.innerText = `The alias cannot be more than ${err.AliasTooLong} characters.`;
        document.getElementById(`alias_${id}`).focus();
      } else if ("TooManyCanisters" in err) {
        error_p.innerText = `You have reached the maximum number of canisters allowed per user: ${err.TooManyCanisters}.`;
      } else {
        error_p.innerText = "Unknown error. Please try again later.";
      }
    }
  } catch (err) {
    console.log(err.message);
    error_p.innerText =
      "Error reaching tipjar canister. Please try again later.";
  }
  save_btn.disabled = false;
  cancel_btn.disabled = false;
  alias_spinner.hidden = true;
  allocated_spinner.hidden = true;
}

function show_canister(tr, allocation, autofocus = false) {
  let id = allocation.canister.id;
  tr.innerHTML = [
    `<td colspan='3'><a>${formatAlias(allocation)}</a><br>`,
    "<div class='center'><div class='table-inner'>",
    `<label class='input-label' for='alias_${id}'><b>Alias</b></label><div class="input-box-wrapper"><div id="alias_${id}_spinner" hidden><i class="fas fa-spinner fa-spin"></i></div><input autocomplete="off" id='alias_${id}' value='${allocation.alias}' /></div><br>`,
    `<label class='input-label' for='allocated_${id}'><b>Allocated</b></label><div class="input-box-wrapper"><div id="allocated_${id}_spinner" hidden><i class="fas fa-spinner fa-spin"></i></div><input autocomplete="off" id='allocated_${id}' value='${formatCycle(
      allocation.allocated
    )}T' /></div><br>`,
    canister_summary(allocation),
    `<p class='error' id='save_canister_error_${id}'></p><div class='center'>`,
    `<button class='canister-button' id='save_canister_${id}'>Save</button>`,
    `<button class='canister-button' id='cancel_canister_${id}'>Cancel</button>`,
    "</div></p>",
    "</div></div></td>",
  ].join("");
  document.getElementById(`save_canister_${id}`).onclick = () => {
    save_canister(tr, id, allocation);
  };
  document.getElementById(`cancel_canister_${id}`).onclick = () => {
    tr.innerHTML = canister_row(allocation);
    document.getElementById("anchor_" + id).onclick = () => {
      show_canister_by_id(id);
    };
  };
  if (autofocus) {
    let inp = document.getElementById(`allocated_${id}`);
    inp.select();
    inp.focus();
  }
}

function show_canister_by_id(id) {
  console.log("(" + id + ")");
  let allocation = find_canister_allocation(id);
  console.log(allocation);
  if (!allocation) return;
  let tr = document.getElementById(id);
  if (!tr) return;
  show_canister(tr, allocation, true);
}

// remove an element to the end of the array if we found it.
function move_to_last(allocations, id) {
  var i;
  let n = allocations.length;
  for (i = 0; i < n; i++) {
    if (allocations[i].canister.id == id) {
      break;
    }
  }
  if (i < n - 1) {
    let tmp = allocations[i];
    allocations[i] = allocations[n - 1];
    allocations[n - 1] = tmp;
  }
}

function show_canisters(allocations) {
  let allocs = [...allocations]; // clone first to avoid mutating it in place
  let tbody = document.getElementById("canisters");
  while (tbody.children.length > allocs.length + 1) {
    tbody.removeChild(tbody.children[0]);
  }
  let rows = tbody.children;
  let lastRow = tbody.children[rows.length - 1];
  for (var i = 0; i < allocations.length; i++) {
    if (i + 1 < rows.length) {
      let existing_id = tbody.children[i].id;
      move_to_last(allocs, existing_id);
    }
    let allocation = allocs.pop();
    let id = allocation.canister.id.toString();
    let row = canister_row(allocation);
    if (i + 1 < rows.length) {
      if (rows[i].children.length == 1) {
        show_canister(rows[i], allocation);
        continue;
      } else {
        rows[i].innerHTML = row;
      }
    } else {
      let tr = document.createElement("tr");
      tr.id = id;
      tr.innerHTML = row;
      lastRow.insertAdjacentElement("beforebegin", tr);
    }
    document.getElementById("anchor_" + id).onclick = () => {
      show_canister_by_id(id);
    };
  }
}

var last_user_id;
// This function is only called from refresh() and save_canister(), where
// full user info is known.
function update_user_info(info) {
  let user_info = agent.get_user_info();
  let id = info.id.toString();
  if (
    !user_info ||
    id != last_user_id ||
    info.last_updated > user_info.last_updated
  ) {
    last_user_id = id;
    agent.set_user_info(info);
    console.log(info);
    show_account_balance(info);
    show_canisters(info.allocations);
    refresh_stats();
  }
}

function clear_user_info() {
  document.getElementById("icp_balance").value = "";
  document.getElementById("cycle_balance").value = "";
  console.log("clear_user_info");
  show_canisters([]);
}

var refreshing = false;
async function refresh() {
  if (!refreshing) {
    refreshing = true;
    try {
      let info = await agent.tipjar_aboutme();
      update_user_info(info);
    } catch (err) {
      console.log(err);
    }
    refreshing = false;
  }
}

async function ping() {
  try {
    let balance = await agent.ledger_account_balance();
    let user_info = agent.get_user_info();
    if (user_info && balance.e8s != user_info.balance.icp.e8s) {
      user_info.balance.icp.e8s = balance.e8s;
      show_account_balance(user_info);
      agent.tipjar_ping().catch((err) => {
        console.log(err);
      });
    }
  } catch (err) {
    console.log(err);
  }
}

function hide_add_canister_form(evt) {
  if (evt) evt.preventDefault();
  document.getElementById("logout_button").hidden = !agent.is_authenticated();
  document.getElementById("add_canister_form").hidden = true;
  document.getElementById("add_canister_anchor").hidden = false;
}

function explain_canister_status_error(msg) {
  var reason = "Error getting the canister's status. Please try again later.";
  let reject_code = msg.indexOf("Reject code: 4");
  let reject_text = msg.indexOf("Reject text: ");
  if (reject_code > 0 && reject_text > 0) {
    reason = msg.substring(reject_text + 13);
  }
  if (msg.indexOf("Only the controllers") >= 0) {
    reason =
      "Cannot obtain this canister's status. " +
      "Please ask its developer to <a href='#why-am-i-getting-an-error-when-trying-to-add-a-canister'>add the black hole canister" +
      " e3mmv-5qaaa-aaaah-aadma-cai</a> to its controller list.";
  }
  return reason;
}
async function add_canister(evt) {
  var canister_id;
  let error_p = document.getElementById("add_canister_error");
  error_p.innerText = "";
  try {
    canister_id = Principal.fromText(
      document.getElementById("new_canister_id").value.trim()
    );
  } catch (err) {
    console.log(err);
    error_p.innerText = "Please input a valid Canister ID.";
    return;
  }
  if (find_canister_allocation(canister_id)) {
    error_p.innerText = "You have already added this canister.";
    return;
  }

  document.getElementById("new_canister_spinner").hidden = false;
  document.getElementById("commit_add_canister").blur();
  document.getElementById("commit_add_canister").disabled = true;
  document.getElementById("cancel_add_canister").disabled = true;
  try {
    let result = await agent.tipjar_allocate({
      canister: canister_id,
      allocated: 0n,
      alias: [],
    });
    console.log(result);
    if (result.ok) {
      refresh_stats();
      update_user_info(result.ok);
      document.getElementById("new_canister_id").value = "";
      hide_add_canister_form();
    } else {
      let err = result.err;
      if ("AccessDenied" in err) {
        error_p.innerText =
          "Only beta testing users can add canisters. Please contact admin for access.";
      } else if ("UserDoesNotExist" in err) {
        error_p.innerText =
          "You need to send in some ICPs first before adding a canister.";
      } else if ("CanisterStatusError" in err) {
        error_p.innerHTML = explain_canister_status_error(
          err.CanisterStatusError
        );
      } else {
        error_p.innerText = "Unknown error. Please try again later.";
      }
    }
  } catch (err) {
    console.log(err.message);
    error_p.innerText =
      "Error reaching tipjar canister. Please try again later.";
  }
  document.getElementById("new_canister_spinner").hidden = true;
  document.getElementById("commit_add_canister").disabled = false;
  document.getElementById("cancel_add_canister").disabled = false;
}

var refresh_interval;
var ping_interval;
function update_login_status() {
  document.getElementById("add_canister_msg").innerText = "";
  let logout_spinner = document.getElementById("logout_spinner");
  let logout_btn = document.getElementById("logout_button");
  logout_btn.onclick = async () => {
    logout_spinner.hidden = false;
    clear_user_info();
    await agent.logout();
    logout_spinner.hidden = true;
    update_login_status();
    document.getElementById("banner_error").innerText = "You have logged out.";
  };
  if (agent.is_authenticated()) {
    document.getElementById("login_box").hidden = true;
    document.getElementById("qr_box").hidden = false;
    document.getElementById("info_parent").classList.remove("hide-div-mobile");
    document.getElementById("top_info").classList.remove("blur");
    document.getElementById("temporary_account").onclick = () => {
      document.getElementById("banner_error").innerText =
        "Please logout first before switching to a temporary account.";
    };
    logout_btn.hidden = false;
  } else if (agent.is_temporary()) {
    document.getElementById("login_box").hidden = false;
    document.getElementById("qr_box").hidden = true;
    document.getElementById("info_parent").classList.remove("hide-div-mobile");
    document.getElementById("top_info").classList.remove("blur");
    logout_btn.hidden = false;
    document.getElementById("temporary_account").onclick = null;
    document.getElementById("banner_error").innerText =
      "You are on a temporary account.";
  } else {
    // anonymous
    document.getElementById("login_box").hidden = false;
    document.getElementById("qr_box").hidden = true;
    document.getElementById("info_parent").classList.add("hide-div-mobile");
    document.getElementById("top_info").classList.add("blur");
    logout_btn.hidden = true;
    document.getElementById("temporary_account").onclick = start_temporary;
    document.getElementById("banner_error").innerText = "";
  }
  show_account_id();
  refresh();
  /// refresh every 5s
  if (!refresh_interval) {
    refresh_interval = setInterval(refresh, 5100);
  }
  if (!ping_interval) {
    ping_interval = setInterval(ping, 6100);
  }
}

async function start_ii_login() {
  let login_spinner = document.getElementById("login_spinner");
  let login_btn = document.getElementById("login_button");
  document.getElementById("banner_error").innerText = "";
  login_spinner.hidden = false;
  login_btn.disabled = true;
  login_btn.blur();
  hide_account();
  await agent.ii_login(async () => {
    await refresh();
    login_spinner.hidden = true;
    login_btn.disabled = false;
    show_account_id();
    if (!agent.is_authenticated()) {
      document.getElementById("banner_error").innerText =
        "Internet Identity login failed. Please try again later.";
    }
  });
}

function readFileContent(file) {
  const reader = new FileReader();
  return new Promise((resolve, reject) => {
    reader.onload = (event) => resolve(event.target.result);
    reader.onerror = (error) => reject(error);
    reader.readAsText(file);
  });
}

function show_add_canister_form(evt) {
  if (evt) evt.preventDefault();
  document.getElementById("add_canister_msg").innerText = "";
  if (agent.is_anonymous()) {
    document.getElementById("add_canister_msg").innerText =
      "Please login before adding a canister.";
    return;
  }
  document.getElementById("logout_button").hidden = !agent.is_authenticated();
  document.getElementById("add_canister_form").hidden = false;
  document.getElementById("add_canister_anchor").hidden = true;
  document.getElementById("commit_add_canister").onclick = add_canister;
  document.getElementById("cancel_add_canister").onclick =
    hide_add_canister_form;
}

agent = new Agent(update_login_status);

async function start_pem_login(evt) {
  let import_pem_anchor = document.getElementById("import_pem_anchor");
  let choose_pem_file = document.getElementById("choose_pem_file");
  const input = evt.target;
  if ("files" in input && input.files.length > 0) {
    let file = input.files[0];
    let content = await readFileContent(file);
    let result = await decodeIdentity(content);
    if (result.err) {
      document.getElementById("banner_error").innerText = result.err;
      return;
    }
    let identity = result.ok;
    console.log("Loaded new identity: ", identity.toJSON());
    login_spinner.hidden = false;
    await agent.activate_pem_client(identity);
    login_spinner.hidden = true;
  }
}

function start_temporary(evt) {
  agent.activate_local_client();
}

function getScroll() {
  if (window.pageYOffset != undefined) {
    return [pageXOffset, pageYOffset];
  } else {
    var sx,
      sy,
      d = document,
      r = d.documentElement,
      b = d.body;
    sx = r.scrollLeft || b.scrollLeft || 0;
    sy = r.scrollTop || b.scrollTop || 0;
    return [sx, sy];
  }
}

function scrollIntoView(selector, offset = 0) {
  window.scroll(0, document.querySelector(selector).offsetTop - offset);
}

async function hide_faq() {
  document.getElementById("info_section").hidden = false;
  document.getElementById("canister_section").hidden = false;
  document.getElementById("faq_section").hidden = true;
}

async function show_faq() {
  let response = await fetch("faq.html");
  let html = await response.text();
  document.getElementById("info_section").hidden = true;
  document.getElementById("canister_section").hidden = true;
  document.getElementById("faq_section").hidden = false;
  document.getElementById("faq_section").innerHTML =
    '<nav><a href="#"><i class="fas fa-angle-double-left"></i> Back</a></nav><h4 style="margin-top: 0">Frequently Asked Questions</h4>' +
    html;
}

var scroll_pos = {};
async function set_location(oldURL, newURL) {
  console.log(newURL);
  var section_id = 0;
  if (oldURL) {
    scroll_pos[oldURL] = getScroll();
  }
  if (newURL.endsWith("/") || newURL.endsWith("/#")) {
    hide_faq();
  } else {
    if (!oldURL || oldURL.endsWith("/") || oldURL.endsWith("/#")) {
      await show_faq();
    }
    let i = newURL.indexOf("#");
    if (i > 0) {
      section_id = newURL.substring(i, newURL.length);
    }
  }
  if (section_id && section_id != "#faq_section") {
    scrollIntoView(section_id);
  } else if (scroll_pos[newURL]) {
    window.scrollTo(scroll_pos[newURL][0], scroll_pos[newURL][1]);
  } else {
    window.scrollTo(0, 0);
  }
}

window.onhashchange = async (evt) => {
  set_location(evt.oldURL, evt.newURL);
};

window.onload = () => {
  if (!last_account_id) {
    hide_account();
  }
  document.getElementById("show_qrcode_anchor").onclick = (evt) => {
    if (evt) evt.preventDefault();
    let show_qrcode = document.getElementById("show_qrcode");
    show_qrcode.classList.add("hide-div");
    show_qrcode.classList.remove("show-div-mobile");
    let account_qrcode = document.getElementById("account_qrcode");
    account_qrcode.classList.add("show-div");
    account_qrcode.classList.remove("hide-div-mobile");
  };
  document.getElementById("how-it-works").onclick = show_faq;
  document.getElementById("login_button").onclick = start_ii_login;
  document.getElementById("add_canister").onclick = show_add_canister_form;
  let import_pem_anchor = document.getElementById("import_pem_anchor");
  let choose_pem_file = document.getElementById("choose_pem_file");
  import_pem_anchor.onclick = () => {
    choose_pem_file.click();
  };
  choose_pem_file.addEventListener("change", start_pem_login);
  refresh_stats();
};

set_location(null, document.location.href);
