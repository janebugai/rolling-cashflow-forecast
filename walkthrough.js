/* Data governance walkthrough. Amounts are read from the sample files. */

(function () {
  var EXAMPLE_IDS = ["PAY-MIN-EQ-2026-02", "INV-PWR-2026-02"];
  var FILES = {
    operating: "data/raw/operating_payments.csv",
    capital: "data/raw/capital_payments.csv",
    mapping: "data/transformed/activity_mapping.csv",
    transactions: "data/transformed/cash_transactions.csv",
    lines: "data/reporting/actual_cash_flow_lines.csv"
  };
  var MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
  var model = null;

  function esc(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function asNumber(value) {
    var n = Number(value);
    return Number.isFinite(n) ? n : 0;
  }

  function formatUsd(value) {
    var n = asNumber(value);
    var abs = Math.abs(n);
    var digits = Math.round(abs) === abs ? 0 : 2;
    var text = abs.toLocaleString("en-US", {
      minimumFractionDigits: digits,
      maximumFractionDigits: digits
    });
    return (n < 0 ? "\u2212$" : "$") + text;
  }

  function amountClass(value) {
    return asNumber(value) < 0 ? "wt-amt wt-amt-neg" : "wt-amt wt-amt-pos";
  }

  function formatLongDate(iso) {
    var parts = String(iso).split("-");
    var month = MONTHS[Number(parts[1]) - 1] || parts[1];
    return month + " " + Number(parts[2]) + ", " + parts[0];
  }

  function formatMonth(iso) {
    var parts = String(iso).split("-");
    var month = MONTHS[Number(parts[1]) - 1] || parts[1];
    return month + " " + parts[0];
  }

  function joinAnd(items) {
    if (items.length < 2) return items.join("");
    if (items.length === 2) return items[0] + " and " + items[1];
    return items.slice(0, -1).join(", ") + ", and " + items[items.length - 1];
  }

  function showLoadMessage(message) {
    var loading = document.getElementById("wt-loading");
    loading.hidden = false;
    loading.textContent = message;
  }

  function resultBadge(pass) {
    var label = pass ? "Pass" : "Review";
    var cls = pass ? "wt-pass" : "wt-review";
    return "<span class=\"wt-result " + cls + "\">" + label + "</span>";
  }

  function assessIds(transactions, paymentIds) {
    var ids = transactions.map(function (row) { return String(row.transaction_id || "").trim(); });
    var blanks = ids.filter(function (id) { return id === ""; }).length;
    var counts = {};
    ids.forEach(function (id) {
      if (id) counts[id] = (counts[id] || 0) + 1;
    });
    var repeated = Object.keys(counts).filter(function (id) { return counts[id] > 1; });
    var selectedMiss = paymentIds.filter(function (id) { return counts[id] !== 1; });
    var pass = ids.length > 0 && blanks === 0 && repeated.length === 0 && selectedMiss.length === 0;
    var detail;
    if (pass) {
      detail = ids.length + " transaction IDs in cash_transactions.csv are present, and each value appears once. " + joinAnd(paymentIds) + " each appear once.";
    } else if (!ids.length) {
      detail = "No transaction IDs were loaded from cash_transactions.csv.";
    } else {
      detail = blanks + " blank transaction IDs and " + repeated.length + " repeated IDs need review. " + joinAnd(paymentIds) + " must each appear once.";
    }
    return { pass: pass, title: "Transaction IDs are present and unique.", detail: detail };
  }

  function assessMapping(payment, txn, mapping) {
    var category = String(payment.source_category || "").trim();
    var rule = mapping.find(function (row) {
      return row.source === payment.mapping_source && row.category === category;
    });
    var pass = !!(rule && txn
      && txn.source_category === rule.category
      && txn.business_activity === rule.business_activity
      && txn.cash_flow_section === rule.cash_flow_section
      && txn.reporting_line === rule.reporting_line);
    var classified = txn
      ? [txn.cash_flow_section || "unclassified", txn.business_activity || "unassigned", txn.reporting_line || "unmapped"].join(" / ")
      : "";
    var detail;
    if (!rule) {
      detail = "No shared mapping row matches " + payment.mapping_source + " / " + (category || "a blank category") + ".";
    } else if (!txn) {
      detail = "The transformed payment is missing, so its classification cannot be compared with the shared mapping.";
    } else if (pass) {
      detail = payment.id + " is classified as " + classified + ", matching the shared mapping for " + category + ".";
    } else {
      detail = payment.id + " is " + classified + ", which does not match the shared mapping (" + [rule.cash_flow_section, rule.business_activity, rule.reporting_line].join(" / ") + ").";
    }
    return {
      pass: pass,
      title: payment.id + " matches the shared mapping.",
      detail: detail,
      rule: rule || null
    };
  }

  function assessLineSum(txn, transactions, lines) {
    var related = transactions.filter(function (row) {
      return row.reporting_month === txn.reporting_month && row.reporting_line === txn.reporting_line;
    });
    var sum = related.reduce(function (total, row) {
      return total + asNumber(row.signed_amount_usd);
    }, 0);
    var reported = lines.find(function (row) {
      return row.reporting_month === txn.reporting_month && row.reporting_line === txn.reporting_line;
    });
    var reportedAmount = reported ? asNumber(reported.signed_amount_usd) : NaN;
    var pass = related.length > 0 && Number.isFinite(reportedAmount) && Math.round(sum) === Math.round(reportedAmount);
    var month = formatMonth(txn.reporting_month);
    var detail;
    if (!reported) {
      detail = "No monthly reporting row was found for " + txn.reporting_line + " in " + month + ".";
    } else if (pass) {
      detail = related.length + " transaction" + (related.length === 1 ? "" : "s") + " behind " + txn.reporting_line + " for " + month + " " + (related.length === 1 ? "sums" : "sum") + " to " + formatUsd(sum) + ", matching the reported amount of " + formatUsd(reportedAmount) + ".";
    } else {
      detail = "Transactions behind " + txn.reporting_line + " for " + month + " sum to " + formatUsd(sum) + ". The reported amount is " + formatUsd(reportedAmount) + ".";
    }
    return { pass: pass, title: "Transactions behind its monthly reporting line sum to the reported amount.", detail: detail, sum: sum, reported: reported };
  }

  function sourceRecord(row, idField, categoryField, mappingSource) {
    return {
      id: row[idField],
      vendor: row.vendor,
      payment_date: row.payment_date,
      source_category: row[categoryField],
      amount_paid: row.amount_paid,
      status: row.status,
      mapping_source: mappingSource
    };
  }

  function sourceRecords(data) {
    return data.operating.map(function (row) {
      return sourceRecord(row, "invoice_id", "cost_category", "Operating payments");
    }).concat(data.capital.map(function (row) {
      return sourceRecord(row, "payment_id", "spend_category", "Capital payments");
    }));
  }

  function buildModel(data) {
    var sources = sourceRecords(data);
    var originalRecords = EXAMPLE_IDS.map(function (id) {
      return sources.find(function (row) { return row.id === id; });
    });
    var missing = EXAMPLE_IDS.filter(function (id, index) { return !originalRecords[index]; });
    var rulesRecords = originalRecords.map(function (row) {
      if (!row) return null;
      return {
        payment: row,
        txn: data.transactions.find(function (txnRow) { return txnRow.transaction_id === row.id; })
      };
    });
    var missingTxn = rulesRecords.filter(function (row) { return row && !row.txn; }).map(function (row) { return row.payment.id; });
    if (missing.length || missingTxn.length) {
      var absent = (missing.length ? missing : missingTxn).join(", ");
      return { error: absent + " was not found in the sample files." };
    }
    var sectionOrder = { Operating: 1, Investing: 2, Financing: 3 };
    var bySection = {};
    rulesRecords.forEach(function (record) {
      var name = record.txn.cash_flow_section;
      if (!bySection[name]) {
        bySection[name] = { name: name, amount: 0, order: sectionOrder[name] || 99 };
      }
      bySection[name].amount += asNumber(record.txn.signed_amount_usd);
    });
    var financeParts = Object.keys(bySection).map(function (name) {
      return bySection[name];
    }).sort(function (a, b) { return a.order - b.order; });
    var byActivity = {};
    rulesRecords.forEach(function (record) {
      var name = record.txn.business_activity;
      if (!byActivity[name]) byActivity[name] = { name: name, amount: 0 };
      byActivity[name].amount += asNumber(record.txn.signed_amount_usd);
    });
    var operationParts = Object.keys(byActivity).map(function (name) {
      return byActivity[name];
    });
    var checks = [assessIds(data.transactions, EXAMPLE_IDS)];
    rulesRecords.forEach(function (record) {
      checks.push(assessMapping(record.payment, record.txn, data.mapping));
      checks.push(assessLineSum(record.txn, data.transactions, data.lines));
    });

    return {
      originalRecords: originalRecords,
      rulesRecords: rulesRecords,
      checks: checks,
      financeParts: financeParts,
      operationParts: operationParts
    };
  }

  function originalRecordRow(payment) {
    return "<tr>"
      + "<td>" + esc(payment.id) + "</td>"
      + "<td>" + esc(payment.vendor) + "</td>"
      + "<td>" + esc(formatLongDate(payment.payment_date)) + "</td>"
      + "<td>" + esc(payment.source_category) + "</td>"
      + "<td class=\"num\">" + esc(formatUsd(payment.amount_paid)) + "</td>"
      + "<td>" + esc(payment.status) + "</td>"
      + "</tr>";
  }

  function renderOriginal(m) {
    return ""
      + "<p>Original details are kept so Finance can always trace a reported number back to its source.</p>"
      + "<div class=\"table-wrap\" tabindex=\"-1\">"
      + "<table class=\"source-table wt-record-table\">"
      + "<thead><tr>"
      + "<th scope=\"col\">Unique ID</th>"
      + "<th scope=\"col\">Vendor</th>"
      + "<th scope=\"col\">Payment date</th>"
      + "<th scope=\"col\">Source category</th>"
      + "<th scope=\"col\" class=\"num\">Amount</th>"
      + "<th scope=\"col\">Status</th>"
      + "</tr></thead>"
      + "<tbody>" + m.originalRecords.map(originalRecordRow).join("") + "</tbody>"
      + "</table></div>";
  }

  function rulesResultRow(record) {
    var payment = record.payment;
    var txn = record.txn;
    return "<tr>"
      + "<td>" + esc(payment.id) + "</td>"
      + "<td>" + esc(formatMonth(txn.reporting_month)) + "</td>"
      + "<td>Credit</td>"
      + "<td>" + esc(txn.cash_flow_section) + "</td>"
      + "<td>" + esc(txn.business_activity) + "</td>"
      + "<td>" + esc(txn.reporting_line) + "</td>"
      + "</tr>";
  }

  function renderRules(m) {
    return ""
      + "<p>Finance approves the rules; Technology maintains their implementation.</p>"
      + "<div class=\"table-wrap\" tabindex=\"-1\">"
      + "<table class=\"source-table wt-record-table\">"
      + "<thead>"
      + "<tr><th scope=\"colgroup\" colspan=\"6\">Original record</th></tr>"
      + "<tr>"
      + "<th scope=\"col\">Unique ID</th>"
      + "<th scope=\"col\">Vendor</th>"
      + "<th scope=\"col\">Payment date</th>"
      + "<th scope=\"col\">Source category</th>"
      + "<th scope=\"col\" class=\"num\">Amount</th>"
      + "<th scope=\"col\">Status</th>"
      + "</tr></thead>"
      + "<tbody>" + m.rulesRecords.map(function (record) { return originalRecordRow(record.payment); }).join("") + "</tbody></table></div>"
      + "<div class=\"table-wrap\" tabindex=\"-1\">"
      + "<table class=\"source-table wt-record-table wt-rules-result\">"
      + "<thead>"
      + "<tr><th scope=\"colgroup\" colspan=\"6\" class=\"wt-rules-head\">Shared rules</th></tr>"
      + "<tr>"
      + "<th scope=\"col\">Unique ID</th>"
      + "<th scope=\"col\">Reporting month</th>"
      + "<th scope=\"col\">Transaction Type</th>"
      + "<th scope=\"col\">Cash-flow category</th>"
      + "<th scope=\"col\">Business activity</th>"
      + "<th scope=\"col\">Reporting line</th>"
      + "</tr></thead>"
      + "<tbody>" + m.rulesRecords.map(rulesResultRow).join("") + "</tbody></table></div>";
  }

  function exampleCard(title, detail) {
    return "<li class=\"wt-check\">"
      + "<span class=\"wt-result wt-example\">Example</span>"
      + "<p class=\"wt-check-title\">" + esc(title) + "</p>"
      + "<p class=\"wt-check-detail\">" + esc(detail) + "</p>"
      + "</li>";
  }

  function renderChecks(m) {
    var items = m.checks.map(function (check) {
      return "<li class=\"wt-check\">"
        + resultBadge(check.pass)
        + "<p class=\"wt-check-title\">" + esc(check.title) + "</p>"
        + "<p class=\"wt-check-detail\">" + esc(check.detail) + "</p>"
        + "</li>";
    }).join("");
    var examples = [
      exampleCard(
        "A duplicate record is rejected.",
        "If PAY-MIN-EQ-2026-02 appeared twice, the transformation would stop and report that transaction IDs are not unique. The repeated row would not be written to cash_transactions.csv."
      ),
      exampleCard(
        "An unmapped category is rejected.",
        "If a payment used a source category with no row in activity_mapping.csv, the transformation would stop and ask for that category to be added. Unmapped activity is not assigned to Other."
      )
    ].join("");
    return ""
      + "<ul class=\"wt-checks\">" + items + "</ul>"
      + "<p>These examples show how the same checks treat a problem. They are not in the sample files.</p>"
      + "<ul class=\"wt-checks\">" + examples + "</ul>";
  }

  function renderTeams(m) {
    var parts = m.financeParts.map(function (part) {
      return "<li>" + esc(part.name) + ": <span class=\"" + amountClass(part.amount) + "\">" + esc(formatUsd(part.amount)) + "</span></li>";
    }).join("");
    var lineItems = m.operationParts.map(function (part) {
      return "<li>" + esc(part.name) + ": <span class=\"" + amountClass(part.amount) + "\">" + esc(formatUsd(part.amount)) + "</span></li>";
    }).join("");
    return ""
      + "<p>Finance defines how cash flows are classified, such as Operating and Investing, while Operations reviews payments by business activity, such as Bitcoin mining operations, and resolves questions about the source data. Technology maintains the pipeline and validation checks that support both teams. This shared foundation lets each team analyze the data from its own perspective while arriving at consistent numbers when using the same scope and reporting period.</p>"
      + "<div class=\"wt-teams\">"
      + "<article class=\"wt-card\"><h4>Finance</h4>"
      + "<ul>" + parts + "</ul>"
      + "</article>"
      + "<article class=\"wt-card\"><h4>Operations</h4>"
      + "<ul>" + lineItems + "</ul>"
      + "</article>"
      + "</div>";
  }

  function renderPanels() {
    var views = [renderOriginal, renderRules, renderChecks, renderTeams];
    views.forEach(function (render, index) {
      document.getElementById("wt-panel-" + (index + 1)).innerHTML = render(model);
    });
  }

  function selectStep(index, source) {
    var tabs = Array.prototype.slice.call(document.querySelectorAll("#governance-walkthrough [role='tab']"));
    tabs.forEach(function (tab, tabIndex) {
      var selected = tabIndex === index;
      tab.setAttribute("aria-selected", selected ? "true" : "false");
      tab.tabIndex = selected ? 0 : -1;
      var panel = document.getElementById(tab.getAttribute("aria-controls"));
      if (panel) panel.hidden = !selected;
    });
    if (source === "keys" && tabs[index]) tabs[index].focus();
  }

  function bind() {
    var tabs = Array.prototype.slice.call(document.querySelectorAll("#governance-walkthrough [role='tab']"));
    tabs.forEach(function (tab, index) {
      tab.addEventListener("click", function () { selectStep(index, "click"); });
      tab.addEventListener("keydown", function (event) {
        var next = index;
        if (event.key === "ArrowRight" || event.key === "ArrowDown") next = (index + 1) % tabs.length;
        else if (event.key === "ArrowLeft" || event.key === "ArrowUp") next = (index - 1 + tabs.length) % tabs.length;
        else if (event.key === "Home") next = 0;
        else if (event.key === "End") next = tabs.length - 1;
        else return;
        event.preventDefault();
        selectStep(next, "keys");
      });
    });
  }

  function start(data) {
    model = buildModel(data);
    if (model.error) {
      showLoadMessage(model.error);
      return;
    }
    renderPanels();
    bind();
    document.getElementById("wt-loading").hidden = true;
    document.getElementById("wt-app").hidden = false;
    selectStep(0, "init");
  }

  Promise.all([
    fetchCsv(FILES.operating),
    fetchCsv(FILES.capital),
    fetchCsv(FILES.mapping),
    fetchCsv(FILES.transactions),
    fetchCsv(FILES.lines)
  ]).then(function (loaded) {
    start({
      operating: loaded[0],
      capital: loaded[1],
      mapping: loaded[2],
      transactions: loaded[3],
      lines: loaded[4]
    });
  }).catch(function () {
    showLoadMessage("Could not read the sample files for the data governance walkthrough. Serve this folder and open cashflow-forecast.html over http.");
  });
})();
