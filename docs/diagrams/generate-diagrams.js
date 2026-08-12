const fs = require("fs");
const path = require("path");

const outDir = __dirname;

function esc(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function lines(x, y, values, cls, anchor = "start", gap = 25) {
  return values.map((value, index) =>
    `<text x="${x}" y="${y + index * gap}" class="${cls}" text-anchor="${anchor}">${esc(value)}</text>`
  ).join("\n");
}

function box(x, y, w, h, title, body, fill, titleSize = "heading") {
  return `<g>
    <rect class="box" x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}"/>
    <text x="${x + w / 2}" y="${y + 38}" class="${titleSize}" text-anchor="middle">${esc(title)}</text>
    ${lines(x + 24, y + 76, body, "body", "start", 28)}
  </g>`;
}

function pathArrow(d, cls = "wire") {
  return `<path class="${cls}" d="${d}"/>`;
}

function architectureSvg() {
  const wires = [];

  // Four keypad word-line outputs, reader -> keypad.
  ["WL0 / uo[0]", "WL1 / uo[1]", "WL2 / uo[2]", "WL3 / uo[3]"].forEach((label, i) => {
    const y = 315 + i * 38;
    wires.push(pathArrow(`M790 ${y} H440`, "wire-left"));
    wires.push(`<text x="600" y="${y - 8}" class="wire-label" text-anchor="middle">${label}</text>`);
  });

  // Four keypad bit-line inputs, keypad -> reader.
  ["BL0 / ui[0]", "BL1 / ui[1]", "BL2 / ui[2]", "BL3 / ui[3]"].forEach((label, i) => {
    const y = 495 + i * 38;
    wires.push(pathArrow(`M440 ${y} H790`, "wire"));
    wires.push(`<text x="600" y="${y - 8}" class="wire-label" text-anchor="middle">${label}</text>`);
  });

  // Seven independent control-button wires into the lower half of button_reader.
  [
    ["ADD / ui[4]", 730],
    ["SUB / ui[5]", 770],
    ["MUL / ui[6]", 810],
    ["DIV / ui[7]", 850],
    ["EQ / uio[4]", 890],
    ["AC / uio[5]", 930],
    ["NEG / uio[6]", 970],
  ].forEach(([label, y]) => {
    wires.push(pathArrow(`M440 ${y} H790`, "wire"));
    wires.push(`<text x="615" y="${y - 9}" class="wire-label" text-anchor="middle">${label}</text>`);
  });

  // Signed-mode select bypasses button_reader and goes directly to the core.
  wires.push(pathArrow("M440 1040 H1205 V790 H1290", "wire"));
  wires.push(`<text x="650" y="1025" class="wire-label" text-anchor="middle">NEG_EN / uio[7] → calculator_core</text>`);

  // Four individual operation indicator outputs.
  ["ADD / uio[0]", "SUB / uio[1]", "MUL / uio[2]", "DIV / uio[3]"].forEach((label, i) => {
    const y = 580 + i * 38;
    wires.push(pathArrow(`M1690 ${y} H2320`, "wire"));
    wires.push(`<text x="2010" y="${y - 8}" class="wire-label" text-anchor="middle">${label}</text>`);
  });

  // Four individual shift-register wires.
  ["SER / uo[4]", "SRCLK / uo[5]", "RCLK / uo[6] (rising-edge latch)", "OE_n / uo[7]"].forEach((label, i) => {
    const y = 1050 + i * 42;
    wires.push(pathArrow(`M1690 ${y} H2320`, "wire"));
    wires.push(`<text x="2010" y="${y - 9}" class="wire-label" text-anchor="middle">${label}</text>`);
  });

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="2900" height="1540" viewBox="0 0 2900 1540" role="img" aria-labelledby="title desc">
  <title id="title">Tiny Calculator detailed design architecture and wire-level pin connections</title>
  <desc id="desc">Detailed architecture showing each keypad, button, mode, operation indicator, and shift-register wire separately, with grouped buses only for valid-ready transactions.</desc>
  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#334155"/></marker>
    <marker id="arrow-blue" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="2.4" markerHeight="2.4" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10z" fill="#2563eb"/></marker>
    <style>
      .title{font:700 38px Arial,sans-serif;fill:#0f172a}.subtitle{font:400 19px Arial,sans-serif;fill:#475569}
      .heading{font:700 24px Arial,sans-serif;fill:#0f172a}.small-heading{font:700 20px Arial,sans-serif;fill:#0f172a}
      .body{font:400 17px Arial,sans-serif;fill:#334155}.small{font:400 15px Arial,sans-serif;fill:#475569}
      .wire-label{font:600 15px Arial,sans-serif;fill:#334155}.bus-label{font:600 16px Arial,sans-serif;fill:#1d4ed8}
      .box{stroke:#334155;stroke-width:2.5;rx:18}.boundary{fill:none;stroke:#94a3b8;stroke-width:3;stroke-dasharray:10 8;rx:24}.divider{stroke:#64748b;stroke-width:2;stroke-dasharray:8 7}
      .wire{fill:none;stroke:#334155;stroke-width:2.5;marker-end:url(#arrow)}.wire-left{fill:none;stroke:#334155;stroke-width:2.5;marker-end:url(#arrow)}
      .bus{fill:none;stroke:#2563eb;stroke-width:8;marker-start:url(#arrow-blue);marker-end:url(#arrow-blue)}
    </style>
  </defs>
  <rect width="2900" height="1540" fill="#f8fafc"/>
  <text x="60" y="62" class="title">Tiny Calculator: detailed architecture and physical wires</text>
  <text x="60" y="98" class="subtitle">Every external signal is drawn separately. Thick blue links are the only grouped valid/ready transaction buses.</text>

  ${box(70, 205, 370, 455, "4x4 Hexadecimal Keypad", ["Each pressed key shorts one active", "word line to one bit line.", "", "WL0 → digits 0 1 2 3", "WL1 → digits 4 5 6 7", "WL2 → digits 8 9 A B", "WL3 → digits C D E F"], "#fef3c7")}
  ${box(70, 690, 370, 390, "Control Hardware", ["Seven active-high buttons:", "+  −  ×  ÷  =  AC  NEG", "", "One mode switch:", "NEG_EN", "", "Use a pull-down resistor", "on every active-high input."], "#ffedd5")}

  <rect class="boundary" x="730" y="155" width="1550" height="1230"/>
  <text x="760" y="190" class="small-heading">tt_um_ag2048_tiny_calculator</text>

  <g>
    <rect class="box" x="790" y="215" width="340" height="815" fill="#dbeafe"/>
    <text x="960" y="255" class="heading" text-anchor="middle">button_reader</text>
    <text x="960" y="292" class="small-heading" text-anchor="middle">matrix-keypad section</text>
    <text x="820" y="332" class="body">4-cycle WL scanner</text>
    <text x="820" y="362" class="body">BL priority decoder</text>
    <text x="820" y="392" class="body">Rightmost pressed BL wins</text>
    <text x="820" y="432" class="small">WL[3:0] → keypad</text>
    <text x="820" y="460" class="small">BL[3:0] ← keypad</text>
    <line x1="815" y1="640" x2="1105" y2="640" class="divider"/>
    <text x="960" y="680" class="small-heading" text-anchor="middle">control-button section</text>
    <text x="820" y="718" class="body">Seven independent input wires</text>
    <text x="820" y="748" class="small">ADD, SUB, MUL, DIV</text>
    <text x="820" y="776" class="small">EQ, AC, NEG</text>
    <text x="820" y="818" class="body">Operation buttons override keypad</text>
    <text x="820" y="848" class="body">Fixed priority: + − × ÷ = AC NEG</text>
    <text x="820" y="900" class="small-heading">shared event output</text>
    <text x="820" y="932" class="small">Wait for full release, then emit:</text>
    <text x="820" y="960" class="small">0xxxx = hex digit</text>
    <text x="820" y="988" class="small">10xxx = operation/control</text>
  </g>
  ${box(1290, 345, 400, 520, "calculator_core", ["25-state user-interface FSM", "A[15:0], B[15:0] registers", "current_op[1:0] register", "Signed entry and display logic", "Chaining and repeated =", "Division-error lock", "", "Own full_adder instance:", "nibble append, NEG, abs(display)"], "#dcfce7")}
  <g>
    <rect class="box" x="1850" y="165" width="400" height="390" fill="#ede9fe"/>
    <text x="2050" y="208" class="heading" text-anchor="middle">alu</text>
    <text x="1885" y="248" class="wire-label">Request from calculator_core</text>
    <text x="1885" y="278" class="body">A[15:0], B[15:0], op[1:0], signed</text>
    <text x="1885" y="308" class="body">input_valid ↔ input_ready</text>
    <line x1="1885" y1="330" x2="2215" y2="330" class="divider"/>
    <text x="1885" y="365" class="wire-label">Response to calculator_core</text>
    <text x="1885" y="395" class="body">result[15:0], error</text>
    <text x="1885" y="425" class="body">result_valid ↔ result_ready</text>
    <line x1="1885" y1="447" x2="2215" y2="447" class="divider"/>
    <text x="1885" y="472" class="wire-label">Datapath</text>
    <text x="1885" y="502" class="body">ADD/SUB; 16-cycle MUL and DIV</text>
    <text x="1885" y="532" class="body">Signed DIV conversion; own full_adder</text>
  </g>
  ${box(1290, 970, 400, 290, "output_driver", ["Hex → active-high a…g", "Leading-zero suppression", "Minus sign and Err patterns", "35 clocks; 29 retained outputs", "Capture SER on falling SRCLK"], "#cffafe")}

  ${box(2320, 480, 420, 260, "Operation Indicators", ["Four independent active-high outputs", "Low-current LED + resistor", "or an external NMOS driver", "", "At most one selected-op line is high"], "#fce7f3")}
  ${box(2320, 890, 420, 410, "External SIPO / LED Driver", ["SIPO = serial-in / parallel-out", "35 clocks; retain 29 useful outputs", "First 6 bits are always-zero dummies", "Capture SER on falling SRCLK", "", "For clean updates, provide either:", "• latch on rising RCLK", "• output blanking via OE_n", "", "Push-pull common-cathode drive", "or external transistor LED drivers"], "#fee2e2")}

  ${wires.join("\n")}

  <path class="bus" d="M1130 430 H1290"/>
  <text x="1210" y="400" class="bus-label" text-anchor="middle">button transaction</text>
  <text x="1210" y="458" class="small" text-anchor="middle">data[4:0], valid ↔ ready</text>

  <path class="bus" d="M1690 430 H1850"/>
  <text x="1770" y="405" class="bus-label" text-anchor="middle">ALU transaction bus</text>

  <path class="bus" d="M1490 865 V970"/>
  <text x="1520" y="910" class="bus-label">display transaction</text>
  <text x="1520" y="937" class="small">data[15:0], error, is_neg, valid ↔ ready</text>

  <rect x="2320" y="1340" width="420" height="145" rx="15" fill="#ffffff" stroke="#cbd5e1" stroke-width="2"/>
  <line x1="2350" y1="1380" x2="2440" y2="1380" class="wire"/><text x="2470" y="1387" class="small">one physical wire</text>
  <line x1="2350" y1="1435" x2="2440" y2="1435" class="bus"/><text x="2470" y="1442" class="small">grouped valid/ready transaction</text>
  </svg>`;

  fs.writeFileSync(path.join(outDir, "architecture.svg"), svg);
}

// Superseded layout retained only as historical generator code; it is never called.
function legacyFsmSvg() {
  const nodeData = {
    AC: [100, 250, "AC", "Clear A, B, op and sign flags", "#fee2e2"],
    DISPLAY_AFTER_AC: [470, 250, "DISPLAY_AFTER_AC", "Offer zero to display driver", "#e0f2fe"],
    WAIT_FIRST_INPUT: [840, 250, "WAIT_FIRST_INPUT", "Wait for A digit, op, NEG or AC", "#dbeafe"],
    FIRST_INPUT_NUMBER: [1210, 250, "FIRST_INPUT_NUMBER", "Append one hex digit to A", "#dbeafe"],
    DISPLAY_AFTER_FIRST_INPUT: [1580, 250, "DISPLAY_AFTER_FIRST_INPUT", "Offer updated A to display", "#e0f2fe"],
    FIRST_INPUT_NEG: [1950, 250, "FIRST_INPUT_NEG", "Two's-complement A; toggle sign flag", "#dbeafe"],
    FIRST_INPUT_OP: [2320, 250, "FIRST_INPUT_OP", "Load +, −, × or ÷ into current_op", "#dcfce7"],

    WAIT_SECOND_INPUT_BEFORE_VALUE: [100, 670, "WAIT_SECOND_INPUT_BEFORE_VALUE", "Operator selected; B has no digit", "#fef3c7"],
    SECOND_INPUT_NEG_BEFORE_VALUE: [520, 670, "SECOND_INPUT_NEG_BEFORE_VALUE", "Toggle negative-entry flag for B", "#fef3c7"],
    COPY_A_TO_B: [940, 670, "COPY_A_TO_B", "Omitted B: copy A into B", "#fef3c7"],
    SECOND_INPUT_NUMBER: [1360, 670, "SECOND_INPUT_NUMBER", "Append one hex digit to B", "#fef3c7"],
    DISPLAY_AFTER_SECOND_INPUT: [1780, 670, "DISPLAY_AFTER_SECOND_INPUT", "Offer updated B to display", "#fff7d6"],
    WAIT_SECOND_INPUT_AFTER_VALUE: [2200, 670, "WAIT_SECOND_INPUT_AFTER_VALUE", "B exists; wait for digit, op, = or NEG", "#fef3c7"],
    SECOND_INPUT_NEG_AFTER_VALUE: [2620, 670, "SECOND_INPUT_NEG_AFTER_VALUE", "Two's-complement B; toggle sign flag", "#fef3c7"],

    SECOND_INPUT_OP_CALCULATE: [100, 1110, "SECOND_INPUT_OP_CALCULATE", "Submit old A op B; queue new op", "#ede9fe"],
    SECOND_INPUT_OP_CALCULATE_WAIT_RESULT: [540, 1110, "SECOND_INPUT_OP_CALCULATE_WAIT_RESULT", "Wait for chained ALU result", "#ede9fe"],
    DISPLAY_AFTER_SECOND_OP: [980, 1110, "DISPLAY_AFTER_SECOND_OP", "Offer chained result A; show new op", "#e0f2fe"],
    EQUAL_AFTER_SECOND_VALUE: [1460, 1110, "EQUAL_AFTER_SECOND_VALUE", "Submit A op B for =", "#ede9fe"],
    EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT: [1880, 1110, "EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT", "Wait for equals ALU result", "#ede9fe"],
    DISPLAY_AFTER_EQUAL: [2320, 1110, "DISPLAY_AFTER_EQUAL", "Offer completed result A to display", "#e0f2fe"],

    WAIT_INPUT_AFTER_EQUAL: [100, 1570, "WAIT_INPUT_AFTER_EQUAL", "Result shown; retain B and current_op", "#cffafe"],
    INPUT_NEG_AFTER_EQUAL: [520, 1570, "INPUT_NEG_AFTER_EQUAL", "Two's-complement displayed result A", "#cffafe"],
    CLEAR_AFTER_EQUAL: [940, 1570, "CLEAR_AFTER_EQUAL", "Clear old calculation before new A", "#cffafe"],
    DISPLAY_ERROR: [1880, 1570, "DISPLAY_ERROR", "Offer Err pattern to display driver", "#fecaca"],
    ERROR_WAIT: [2320, 1570, "ERROR_WAIT", "Ignore every key except AC", "#fecaca"],
  };

  const nodeW = 330;
  const nodeH = 115;
  const center = (id) => [nodeData[id][0] + nodeW / 2, nodeData[id][1] + nodeH / 2];
  const left = (id) => [nodeData[id][0], nodeData[id][1] + nodeH / 2];
  const right = (id) => [nodeData[id][0] + nodeW, nodeData[id][1] + nodeH / 2];
  const top = (id) => [nodeData[id][0] + nodeW / 2, nodeData[id][1]];
  const bottom = (id) => [nodeData[id][0] + nodeW / 2, nodeData[id][1] + nodeH];

  const edge = (d, label, x, y, cls = "auto") => `<path class="edge ${cls}" d="${d}"/><text x="${x}" y="${y}" class="edge-label ${cls}-text" text-anchor="middle">${esc(label)}</text>`;
  const edges = [];

  edges.push(edge(`M${right("AC").join(" ")} H${left("DISPLAY_AFTER_AC")[0]}`, "automatic", 450, 240));
  edges.push(edge(`M${right("DISPLAY_AFTER_AC").join(" ")} H${left("WAIT_FIRST_INPUT")[0]}`, "display accepts zero", 820, 240, "handshake"));
  edges.push(edge(`M${right("WAIT_FIRST_INPUT").join(" ")} H${left("FIRST_INPUT_NUMBER")[0]}`, "hex digit", 1190, 240, "key"));
  edges.push(edge(`M${right("FIRST_INPUT_NUMBER").join(" ")} H${left("DISPLAY_AFTER_FIRST_INPUT")[0]}`, "automatic", 1560, 240));
  edges.push(edge(`M1745 365 V430 H1005 V365`, "display accepts A", 1375, 452, "handshake"));
  edges.push(edge(`M1005 250 V150 H2115 V250`, "NEG", 1560, 138, "key"));
  edges.push(edge(`M2115 365 V500 H1745 V365`, "automatic: show negated A", 1930, 522));
  edges.push(edge(`M1005 365 V535 H2485 V365`, "+ / − / × / ÷", 1745, 557, "key"));
  edges.push(edge(`M2485 365 V540 H265 V670`, "automatic: operation selected", 1380, 562));

  edges.push(edge(`M${right("WAIT_SECOND_INPUT_BEFORE_VALUE").join(" ")} H${left("SECOND_INPUT_NEG_BEFORE_VALUE")[0]}`, "NEG", 500, 660, "key"));
  edges.push(edge(`M685 785 V845 H265 V785`, "automatic", 475, 867));
  edges.push(edge(`M265 785 V930 H1105 V785`, "= : use A as the omitted B", 685, 952, "key"));
  edges.push(edge(`M265 670 V565 H1525 V670`, "hex digit: start B", 895, 553, "key"));
  edges.push(edge(`M${right("SECOND_INPUT_NUMBER").join(" ")} H${left("DISPLAY_AFTER_SECOND_INPUT")[0]}`, "automatic", 1760, 660));
  edges.push(edge(`M${right("DISPLAY_AFTER_SECOND_INPUT").join(" ")} H${left("WAIT_SECOND_INPUT_AFTER_VALUE")[0]}`, "display accepts B", 2180, 660, "handshake"));
  edges.push(edge(`M${right("WAIT_SECOND_INPUT_AFTER_VALUE").join(" ")} H${left("SECOND_INPUT_NEG_AFTER_VALUE")[0]}`, "NEG", 2600, 660, "key"));
  edges.push(edge(`M2785 785 V870 H1945 V785`, "automatic: show negated B", 2365, 892));
  edges.push(edge(`M2365 670 V610 H1525 V670`, "hex digit", 1945, 598, "key"));
  edges.push(edge(`M265 670 V610 H2485 V365`, "another operator replaces current_op", 1375, 598, "key"));

  edges.push(edge(`M2365 785 V980 H265 V1110`, "new operator after B", 1315, 1002, "key"));
  edges.push(edge(`M${right("SECOND_INPUT_OP_CALCULATE").join(" ")} H${left("SECOND_INPUT_OP_CALCULATE_WAIT_RESULT")[0]}`, "ALU accepts request", 520, 1100, "handshake"));
  edges.push(edge(`M${right("SECOND_INPUT_OP_CALCULATE_WAIT_RESULT").join(" ")} H${left("DISPLAY_AFTER_SECOND_OP")[0]}`, "successful result", 960, 1100, "handshake"));
  edges.push(edge(`M1145 1225 V1330 H265 V785`, "display accepts result; wait for next B", 705, 1352, "handshake"));

  edges.push(edge(`M1105 785 V1030 H1625 V1110`, "= with omitted B", 1365, 1052, "key"));
  edges.push(edge(`M2365 785 V1040 H1625 V1110`, "= after B", 2020, 1062, "key"));
  edges.push(edge(`M${right("EQUAL_AFTER_SECOND_VALUE").join(" ")} H${left("EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT")[0]}`, "ALU accepts request", 1860, 1100, "handshake"));
  edges.push(edge(`M${right("EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT").join(" ")} H${left("DISPLAY_AFTER_EQUAL")[0]}`, "successful result", 2300, 1100, "handshake"));
  edges.push(edge(`M2485 1225 V1430 H265 V1570`, "display accepts result", 1375, 1452, "handshake"));

  edges.push(edge(`M${right("WAIT_INPUT_AFTER_EQUAL").join(" ")} H${left("INPUT_NEG_AFTER_EQUAL")[0]}`, "NEG", 500, 1560, "key"));
  edges.push(edge(`M685 1570 V1500 H2485 V1225`, "automatic: redisplay negated result", 1590, 1488));
  edges.push(edge(`M265 1685 V1730 H1105 V1685`, "hex digit: start a new calculation", 685, 1752, "key"));
  edges.push(edge(`M1105 1570 V1490 H1375 V365`, "automatic: first digit becomes new A", 1240, 1478));
  edges.push(edge(`M265 1570 V1370 H1625 V1225`, "= repeats retained operation with retained B", 945, 1392, "key"));
  edges.push(edge(`M265 1685 V1780 H2485 V365`, "operator: continue from result as A", 1375, 1802, "key"));

  edges.push(edge(`M705 1167 V1850 H2045 V1685`, "ALU error", 1375, 1872, "error"));
  edges.push(edge(`M2045 1167 V1570`, "ALU error", 2075, 1450, "error"));
  edges.push(edge(`M${right("DISPLAY_ERROR").join(" ")} H${left("ERROR_WAIT")[0]}`, "display accepts Err", 2300, 1560, "handshake"));
  edges.push(edge(`M2485 1685 V2050 H265 V365`, "AC clears error", 1375, 2072, "key"));

  const nodes = Object.entries(nodeData).map(([id, [x, y, title, description, fill]]) =>
    `<g><rect class="node" x="${x}" y="${y}" width="${nodeW}" height="${nodeH}" fill="${fill}"/>
      <text x="${x + nodeW / 2}" y="${y + 38}" class="node-title" text-anchor="middle">${esc(title)}</text>
      <text x="${x + nodeW / 2}" y="${y + 78}" class="node-body" text-anchor="middle">${esc(description)}</text></g>`
  ).join("\n");

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="3050" height="2260" viewBox="0 0 3050 2260" role="img" aria-labelledby="title desc">
  <title id="title">Detailed calculator_core finite-state machine</title>
  <desc id="desc">All 25 RTL states and their key-driven, automatic, display-handshake, ALU-handshake, success, and error transitions.</desc>
  <defs>
    <marker id="arrow-gray" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#475569"/></marker>
    <marker id="arrow-blue" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#2563eb"/></marker>
    <marker id="arrow-green" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#15803d"/></marker>
    <marker id="arrow-red" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#dc2626"/></marker>
    <style>
      .title{font:700 38px Arial,sans-serif;fill:#0f172a}.subtitle{font:400 19px Arial,sans-serif;fill:#475569}
      .lane-title{font:700 20px Arial,sans-serif;fill:#334155}.node{stroke:#334155;stroke-width:2.3;rx:16}
      .node-title{font:700 12px Consolas,monospace;fill:#0f172a}.node-body{font:400 15px Arial,sans-serif;fill:#334155}
      .edge{fill:none;stroke-width:2.8}.edge.auto{stroke:#475569;marker-end:url(#arrow-gray)}.edge.key{stroke:#2563eb;marker-end:url(#arrow-blue)}
      .edge.handshake{stroke:#15803d;marker-end:url(#arrow-green)}.edge.error{stroke:#dc2626;marker-end:url(#arrow-red)}
      .edge-label{font:600 14px Arial,sans-serif}.auto-text{fill:#475569}.key-text{fill:#1d4ed8}.handshake-text{fill:#166534}.error-text{fill:#b91c1c}
      .note{font:400 16px Arial,sans-serif;fill:#475569}.legend{font:600 15px Arial,sans-serif;fill:#334155}
    </style>
  </defs>
  <rect width="3050" height="2260" fill="#f8fafc"/>
  <text x="60" y="62" class="title">calculator_core FSM: all RTL sub-states and transitions</text>
  <text x="60" y="98" class="subtitle">State names match calculator_core.sv; the second line explains what each short-lived state means to a calculator user.</text>

  <rect x="60" y="190" width="2930" height="260" rx="18" fill="#eff6ff" opacity="0.45"/>
  <text x="75" y="220" class="lane-title">Clear and first-value entry</text>
  <rect x="60" y="610" width="2930" height="280" rx="18" fill="#fffbeb" opacity="0.55"/>
  <text x="75" y="640" class="lane-title">Operator selected and second-value entry</text>
  <rect x="60" y="1050" width="2930" height="300" rx="18" fill="#f5f3ff" opacity="0.5"/>
  <text x="75" y="1080" class="lane-title">ALU submission, wait, and result display</text>
  <rect x="60" y="1510" width="2930" height="250" rx="18" fill="#ecfeff" opacity="0.5"/>
  <text x="75" y="1540" class="lane-title">Actions after equals and error handling</text>

  ${edges.join("\n")}
  ${nodes}

  <rect x="80" y="2130" width="2890" height="85" rx="15" fill="#ffffff" stroke="#cbd5e1" stroke-width="2"/>
  <line x1="115" y1="2160" x2="190" y2="2160" class="edge auto"/><text x="210" y="2167" class="legend">automatic micro-step</text>
  <line x1="520" y1="2160" x2="595" y2="2160" class="edge key"/><text x="615" y="2167" class="legend">button/key transition</text>
  <line x1="950" y1="2160" x2="1025" y2="2160" class="edge handshake"/><text x="1045" y="2167" class="legend">valid/ready handshake or successful response</text>
  <line x1="1580" y1="2160" x2="1655" y2="2160" class="edge error"/><text x="1675" y="2167" class="legend">ALU division-by-zero response</text>
  <text x="2110" y="2167" class="note">AC from any input-wait state → AC. Unhandled keys leave that wait state unchanged.</text>
  </svg>`;

  fs.writeFileSync(path.join(outDir, "fsm.svg"), svg);
}

function buttonArraySvg() {
  const rowY = [360, 590, 820, 1050];
  const colX = [500, 800, 1100, 1400];
  const keys = [
    ["0", "1", "2", "3"],
    ["4", "5", "6", "7"],
    ["8", "9", "A", "B"],
    ["C", "D", "E", "F"],
  ];

  const matrix = [];
  rowY.forEach((y, row) => {
    matrix.push(`<path class="net wl" d="M120 ${y} H1530"/>`);
    matrix.push(`<path class="direction wl" d="M120 ${y} H170"/>`);
    matrix.push(`<text x="125" y="${y - 18}" class="net-label">WL${row} / uo[${row}]</text>`);
    colX.forEach((x, col) => {
      matrix.push(`<g aria-label="Key ${keys[row][col]} between WL${row} and BL${col}">
        <circle cx="${x - 100}" cy="${y}" r="5" fill="#334155"/>
        <circle cx="${x}" cy="${y - 75}" r="5" fill="#334155"/>
        <g transform="translate(${x - 100} ${y}) rotate(-36.87)">
          <path class="component" d="M0 0 H18"/>
          <circle cx="18" cy="0" r="4" fill="#334155"/>
          <circle cx="52" cy="0" r="4" fill="#334155"/>
          <path class="component" d="M18 0 L47 -19"/>
          <path class="component" d="M52 0 H67"/>
          <path class="component" d="M67 -14 L67 14 L89 0 Z"/>
          <path class="component" d="M93 -15 V15"/>
          <path class="component" d="M93 0 H125"/>
        </g>
        <rect x="${x - 120}" y="${y - 112}" width="68" height="30" rx="8" fill="#ffffff" stroke="#cbd5e1"/>
        <text x="${x - 86}" y="${y - 91}" class="key" text-anchor="middle">${keys[row][col]}</text>
      </g>`);
    });
  });

  colX.forEach((x, col) => {
    matrix.push(`<path class="net bl" d="M${x} 220 V1160"/>`);
    matrix.push(`<path class="direction bl" d="M${x} 270 V220"/>`);
    matrix.push(`<text x="${x}" y="205" class="net-label" text-anchor="middle">BL${col} / ui[${col}]</text>`);
    matrix.push(`<path class="component" d="M${x} 1160 V1185 L${x - 16} 1197 L${x + 16} 1213 L${x - 16} 1229 L${x + 16} 1245 L${x - 16} 1261 L${x} 1277 V1295"/>`);
    matrix.push(`<text x="${x + 28}" y="1235" class="small">pull-down</text>`);
    matrix.push(`<path class="ground" d="M${x - 22} 1295 H${x + 22} M${x - 14} 1305 H${x + 14} M${x - 6} 1315 H${x + 6}"/>`);
  });

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1650" height="1450" viewBox="0 0 1650 1450" role="img" aria-labelledby="title desc">
  <title id="title">Tiny Calculator 4x4 hexadecimal keypad matrix</title>
  <desc id="desc">A four-by-four hexadecimal switch matrix. Every key is a diagonal branch from a word line to a bit line, containing one normally-open switch and one series isolation diode. Each bit line has one pull-down resistor.</desc>
  <style>
    .title{font:700 38px Arial,sans-serif;fill:#0f172a}.subtitle{font:400 19px Arial,sans-serif;fill:#475569}
    .section{font:700 25px Arial,sans-serif;fill:#0f172a}.body{font:400 17px Arial,sans-serif;fill:#334155}.small{font:400 15px Arial,sans-serif;fill:#475569}
    .net-label{font:600 15px Consolas,monospace;fill:#334155}
    .key{font:700 17px Consolas,monospace;fill:#0f172a}.net{fill:none;stroke:#334155;stroke-width:3}.wl{stroke:#2563eb}.bl{stroke:#15803d}
    .component{fill:none;stroke:#334155;stroke-width:3;stroke-linejoin:round;stroke-linecap:round}.ground{fill:none;stroke:#334155;stroke-width:3}
    .direction{fill:none;stroke-width:3.5;marker-end:url(#direction-arrow)}
    .panel{stroke:#94a3b8;stroke-width:2.5;rx:20}.note{fill:#ffffff;stroke:#cbd5e1;stroke-width:2;rx:15}
  </style>
  <defs><marker id="direction-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#334155"/></marker></defs>
  <rect width="1650" height="1450" fill="#f8fafc"/>
  <text x="60" y="62" class="title">4×4 hexadecimal keypad matrix</text>
  <text x="60" y="98" class="subtitle">Each normally-open key is a separate diagonal WL-to-BL branch containing a series isolation diode.</text>

  <rect class="panel" x="45" y="130" width="1560" height="1265" fill="#eff6ff"/>
  <text x="75" y="172" class="body">The scanner drives one blue word line high. Closing a switch carries that level diagonally through its diode to one green bit-line input.</text>
  ${matrix.join("\n")}
  <rect class="note" x="75" y="1340" width="1500" height="38"/>
  <text x="95" y="1366" class="small">Diode orientation: anode toward WL, cathode/bar toward BL. Use one diode per key and one pull-down per BL input.</text>
  </svg>`;

  fs.writeFileSync(path.join(outDir, "button-array.svg"), svg);
}

function fsmStyle() {
  return `<defs>
    <marker id="arrow-gray" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#475569"/></marker>
    <marker id="arrow-blue" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#2563eb"/></marker>
    <marker id="arrow-green" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#15803d"/></marker>
    <marker id="arrow-red" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#dc2626"/></marker>
    <style>
      .title{font:700 38px Arial,sans-serif;fill:#0f172a}.subtitle{font:400 19px Arial,sans-serif;fill:#475569}
      .phase-title{font:700 24px Arial,sans-serif;fill:#0f172a}.state{font:700 14px Consolas,monospace;fill:#0f172a}
      .meaning{font:400 16px Arial,sans-serif;fill:#334155}.node{stroke:#334155;stroke-width:2.3;rx:16}
      .node-title{font:700 12px Consolas,monospace;fill:#0f172a}.node-body{font:400 14px Arial,sans-serif;fill:#334155}
      .panel{stroke:#cbd5e1;stroke-width:2;rx:20}.lane-title{font:700 20px Arial,sans-serif;fill:#334155}
      .edge{fill:none;stroke-width:2.8}.edge.auto{stroke:#475569;marker-end:url(#arrow-gray)}.edge.key{stroke:#2563eb;marker-end:url(#arrow-blue)}
      .edge.handshake{stroke:#15803d;marker-end:url(#arrow-green)}.edge.error{stroke:#dc2626;marker-end:url(#arrow-red)}
      .edge-label{font:600 14px Arial,sans-serif;paint-order:stroke;stroke:#f8fafc;stroke-width:11px;stroke-linejoin:round}
      .auto-text{fill:#475569}.key-text{fill:#1d4ed8}.handshake-text{fill:#166534}.error-text{fill:#b91c1c}
      .legend{font:600 15px Arial,sans-serif;fill:#334155}.note{font:400 16px Arial,sans-serif;fill:#475569}
    </style>
  </defs>`;
}

function fsmEdge(d, label, x, y, cls = "auto", anchor = "middle") {
  return `<path class="edge ${cls}" d="${d}"/><text x="${x}" y="${y}" class="edge-label ${cls}-text" text-anchor="${anchor}">${esc(label)}</text>`;
}

function simplifiedFsmSvg() {
  const phase = (x, y, title, fill, rows) => {
    const body = rows.map(([state, meaning], i) => {
      const yy = y + 100 + i * 58;
      return `<text x="${x + 24}" y="${yy}" class="state">${esc(state)}</text>
        <text x="${x + 24}" y="${yy + 24}" class="meaning">${esc(meaning)}</text>`;
    }).join("\n");
    return `<g><rect class="node" x="${x}" y="${y}" width="560" height="560" fill="${fill}"/>
      <text x="${x + 280}" y="${y + 48}" class="phase-title" text-anchor="middle">${esc(title)}</text>
      <line x1="${x + 22}" y1="${y + 68}" x2="${x + 538}" y2="${y + 68}" stroke="#94a3b8" stroke-width="2"/>
      ${body}</g>`;
  };

  const phases = [
    phase(60, 200, "Clear and ready", "#fee2e2", [
      ["AC", "Clear operands, operator, and sign-entry flags"],
      ["DISPLAY_AFTER_AC", "Send zero to the display driver"],
    ]),
    phase(840, 200, "Enter first value (A)", "#dbeafe", [
      ["WAIT_FIRST_INPUT", "Wait for a digit, operator, NEG, or AC"],
      ["FIRST_INPUT_NUMBER", "Append one hexadecimal digit to A"],
      ["DISPLAY_AFTER_FIRST_INPUT", "Display the updated A value"],
      ["FIRST_INPUT_NEG", "Negate A in signed mode, then redisplay"],
      ["FIRST_INPUT_OP", "Store the selected arithmetic operation"],
    ]),
    phase(1620, 200, "Enter second value (B)", "#fef3c7", [
      ["WAIT_SECOND_INPUT_BEFORE_VALUE", "Operator chosen; B has no digit yet"],
      ["SECOND_INPUT_NEG_BEFORE_VALUE", "Prepare negative entry before B's first digit"],
      ["COPY_A_TO_B", "For an omitted B, copy displayed A into B"],
      ["SECOND_INPUT_NUMBER", "Append one hexadecimal digit to B"],
      ["DISPLAY_AFTER_SECOND_INPUT", "Display the updated B value"],
      ["WAIT_SECOND_INPUT_AFTER_VALUE", "Wait for more B, NEG, an operator, or equals"],
      ["SECOND_INPUT_NEG_AFTER_VALUE", "Negate an already-entered B, then redisplay"],
    ]),
    phase(2400, 200, "Calculate or chain", "#ede9fe", [
      ["SECOND_INPUT_OP_CALCULATE", "Submit A op B and remember the new operator"],
      ["SECOND_INPUT_OP_CALCULATE_WAIT_RESULT", "Wait for the chained ALU result"],
      ["DISPLAY_AFTER_SECOND_OP", "Display result A, then wait for a new B"],
      ["EQUAL_AFTER_SECOND_VALUE", "Submit A op B after equals"],
      ["EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT", "Wait for the equals ALU result"],
      ["DISPLAY_AFTER_EQUAL", "Display the completed result A"],
    ]),
    phase(3180, 200, "Result and continuation", "#cffafe", [
      ["WAIT_INPUT_AFTER_EQUAL", "Result shown; retain B and the operation"],
      ["INPUT_NEG_AFTER_EQUAL", "Negate the displayed result, then redisplay"],
      ["CLEAR_AFTER_EQUAL", "A digit clears the old calculation and starts A"],
      ["Repeated equals", "Reuse retained operation and B"],
      ["Operator after result", "Continue with displayed result as A"],
    ]),
  ];

  const errorPhase = `<g><rect class="node" x="2400" y="1010" width="560" height="300" fill="#fecaca"/>
    <text x="2680" y="1058" class="phase-title" text-anchor="middle">Division error</text>
    <line x1="2422" y1="1078" x2="2938" y2="1078" stroke="#94a3b8" stroke-width="2"/>
    <text x="2424" y="1124" class="state">DISPLAY_ERROR</text><text x="2424" y="1148" class="meaning">Send the Err pattern to the display driver</text>
    <text x="2424" y="1206" class="state">ERROR_WAIT</text><text x="2424" y="1230" class="meaning">Ignore inputs until AC clears the calculator</text>
  </g>`;

  const edges = [
    fsmEdge("M20 480 H60", "reset", 30, 464, "auto"),
    fsmEdge("M620 480 H840", "display accepts zero", 730, 464, "handshake"),
    fsmEdge("M1400 480 H1620", "operation selected", 1510, 464, "key"),
    fsmEdge("M2180 480 H2400", "= or operator after B", 2290, 464, "key"),
    fsmEdge("M2960 480 H3180", "successful result", 3070, 464, "handshake"),
    fsmEdge("M2610 760 V1010", "division by zero", 2628, 900, "error", "start"),
    fsmEdge("M3460 200 V115 H1120 V200", "digit: start a new calculation", 2290, 102, "key"),
    fsmEdge("M3580 200 V70 H1900 V200", "operator: continue from displayed result", 2740, 57, "key"),
    fsmEdge("M3340 760 V865 H2680 V760", "= : repeat retained operation and B", 3010, 852, "key"),
    fsmEdge("M2400 1160 H330 V760", "AC", 1335, 1147, "key"),
  ];

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="3800" height="1420" viewBox="0 0 3800 1420" role="img" aria-labelledby="title desc">
  <title id="title">Simplified Tiny Calculator finite-state machine</title>
  <desc id="desc">Six user-facing calculator phases. Each large phase contains the smaller RTL states that implement it.</desc>
  ${fsmStyle()}
  <rect width="3800" height="1420" fill="#f8fafc"/>
  <text x="60" y="62" class="title">Tiny Calculator FSM: user-facing overview</text>
  <text x="60" y="98" class="subtitle">Large boxes are calculator phases. Monospace rows inside them are the actual calculator_core RTL sub-states.</text>
  ${edges.join("\n")}
  ${phases.join("\n")}
  ${errorPhase}
  <text x="60" y="1370" class="note">AC from any input-wait phase returns to Clear and ready. Unhandled buttons leave the current wait state unchanged.</text>
  </svg>`;
  fs.writeFileSync(path.join(outDir, "fsm-simplified.svg"), svg);
}

function detailedFsmSvg() {
  const nodeW = 360;
  const nodeH = 116;
  const nodes = {
    AC: [80, 240, "Clear all calculator state", "#fee2e2"],
    DISPLAY_AFTER_AC: [520, 240, "Offer zero to display", "#e0f2fe"],
    WAIT_FIRST_INPUT: [960, 240, "Wait for first-value input", "#dbeafe"],
    FIRST_INPUT_NUMBER: [1400, 240, "Append one digit to A", "#dbeafe"],
    DISPLAY_AFTER_FIRST_INPUT: [1840, 240, "Offer updated A to display", "#e0f2fe"],
    FIRST_INPUT_OP: [960, 500, "Store selected operation", "#dcfce7"],
    FIRST_INPUT_NEG: [1400, 500, "Negate A and toggle entry sign", "#dbeafe"],

    WAIT_SECOND_INPUT_BEFORE_VALUE: [80, 920, "Operator selected; B empty", "#fef3c7"],
    SECOND_INPUT_NEG_BEFORE_VALUE: [520, 920, "Prepare negative B entry", "#fef3c7"],
    COPY_A_TO_B: [960, 920, "Copy A to omitted B", "#fef3c7"],
    SECOND_INPUT_NUMBER: [1400, 920, "Append one digit to B", "#fef3c7"],
    DISPLAY_AFTER_SECOND_INPUT: [1840, 920, "Offer updated B to display", "#fff7d6"],
    WAIT_SECOND_INPUT_AFTER_VALUE: [2280, 920, "B exists; await next action", "#fef3c7"],
    SECOND_INPUT_NEG_AFTER_VALUE: [2720, 920, "Negate entered B", "#fef3c7"],

    SECOND_INPUT_OP_CALCULATE: [80, 1690, "Submit old op; queue new op", "#ede9fe"],
    SECOND_INPUT_OP_CALCULATE_WAIT_RESULT: [520, 1690, "Wait for chained result", "#ede9fe"],
    DISPLAY_AFTER_SECOND_OP: [960, 1690, "Display chained result A", "#e0f2fe"],
    EQUAL_AFTER_SECOND_VALUE: [1500, 1690, "Submit A op B for equals", "#ede9fe"],
    EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT: [1940, 1690, "Wait for equals result", "#ede9fe"],
    DISPLAY_AFTER_EQUAL: [2380, 1690, "Display completed result A", "#e0f2fe"],
    WAIT_INPUT_AFTER_EQUAL: [2820, 1690, "Result shown; retain op and B", "#cffafe"],
    INPUT_NEG_AFTER_EQUAL: [2380, 1950, "Negate displayed result A", "#cffafe"],
    CLEAR_AFTER_EQUAL: [2820, 1950, "Clear before a new first digit", "#cffafe"],
    DISPLAY_ERROR: [1680, 2460, "Offer Err to display", "#fecaca"],
    ERROR_WAIT: [2120, 2460, "Ignore every input except AC", "#fecaca"],
  };

  const anchor = (id, side, offset = 0) => {
    const [x, y] = nodes[id];
    if (side === "left") return [x, y + nodeH / 2 + offset];
    if (side === "right") return [x + nodeW, y + nodeH / 2 + offset];
    if (side === "top") return [x + nodeW / 2 + offset, y];
    return [x + nodeW / 2 + offset, y + nodeH];
  };
  const point = (value) => value.join(" ");
  const stateNodes = Object.entries(nodes).map(([id, [x, y, meaning, fill]]) =>
    `<g><rect class="node" x="${x}" y="${y}" width="${nodeW}" height="${nodeH}" fill="${fill}"/>
      <text x="${x + nodeW / 2}" y="${y + 38}" class="node-title" text-anchor="middle">${esc(id)}</text>
      <text x="${x + nodeW / 2}" y="${y + 79}" class="node-body" text-anchor="middle">${esc(meaning)}</text></g>`
  ).join("\n");

  const edges = [
    fsmEdge(`M${point(anchor("AC", "right"))} H${anchor("DISPLAY_AFTER_AC", "left")[0]}`, "automatic", 480, 228),
    fsmEdge(`M${point(anchor("DISPLAY_AFTER_AC", "right"))} H${anchor("WAIT_FIRST_INPUT", "left")[0]}`, "display accepts zero", 920, 228, "handshake"),
    fsmEdge(`M${point(anchor("WAIT_FIRST_INPUT", "right"))} H${anchor("FIRST_INPUT_NUMBER", "left")[0]}`, "digit", 1360, 228, "key"),
    fsmEdge(`M${point(anchor("FIRST_INPUT_NUMBER", "right"))} H${anchor("DISPLAY_AFTER_FIRST_INPUT", "left")[0]}`, "automatic", 1800, 228),
    fsmEdge(`M${point(anchor("DISPLAY_AFTER_FIRST_INPUT", "top"))} V150 H1140 V240`, "display accepts A", 1550, 125, "handshake", "end"),
    fsmEdge(`M${point(anchor("WAIT_FIRST_INPUT", "bottom"))} V500`, "operator", 1110, 435, "key", "start"),
    fsmEdge(`M${point(anchor("WAIT_FIRST_INPUT", "bottom", 70))} V430 H1580 V500`, "NEG", 1400, 405, "key"),
    fsmEdge(`M${point(anchor("FIRST_INPUT_NEG", "right"))} H2020 V356`, "automatic: redisplay A", 1890, 546),

    fsmEdge(`M${point(anchor("FIRST_INPUT_OP", "bottom"))} V820 H260 V920`, "operation selected", 700, 795),
    fsmEdge(`M${point(anchor("WAIT_SECOND_INPUT_BEFORE_VALUE", "right", -26))} H520`, "NEG", 480, 940, "key"),
    fsmEdge(`M${point(anchor("SECOND_INPUT_NEG_BEFORE_VALUE", "bottom"))} V1170 H260 V1036`, "automatic", 480, 1145),
    fsmEdge(`M${point(anchor("WAIT_SECOND_INPUT_BEFORE_VALUE", "top", 60))} V860 H1140 V920`, "= : copy A to B", 1040, 847, "key"),
    fsmEdge(`M${point(anchor("WAIT_SECOND_INPUT_BEFORE_VALUE", "bottom", -50))} V1260 H1580 V1036`, "digit: start B", 900, 1235, "key"),
    fsmEdge(`M${point(anchor("WAIT_SECOND_INPUT_BEFORE_VALUE", "left"))} H30 V455 H1020 V500`, "operator: replace selection", 380, 430, "key"),
    fsmEdge(`M${point(anchor("SECOND_INPUT_NUMBER", "right"))} H1840`, "automatic", 1800, 908),
    fsmEdge(`M${point(anchor("DISPLAY_AFTER_SECOND_INPUT", "right"))} H2280`, "display accepts B", 2240, 908, "handshake"),
    fsmEdge(`M${point(anchor("WAIT_SECOND_INPUT_AFTER_VALUE", "right", -24))} H2720`, "NEG", 2680, 940, "key"),
    fsmEdge(`M${point(anchor("SECOND_INPUT_NEG_AFTER_VALUE", "bottom"))} V1320 H2020 V1036`, "automatic: redisplay B", 2460, 1295),
    fsmEdge(`M${point(anchor("WAIT_SECOND_INPUT_AFTER_VALUE", "top", 40))} V840 H1580 V920`, "digit: extend B", 2020, 815, "key"),

    fsmEdge(`M${point(anchor("WAIT_SECOND_INPUT_AFTER_VALUE", "bottom", -100))} V1420 H260 V1690`, "operator after B", 630, 1407, "key"),
    fsmEdge(`M${point(anchor("SECOND_INPUT_OP_CALCULATE", "right"))} H520`, "ALU accepts", 480, 1678, "handshake"),
    fsmEdge(`M${point(anchor("SECOND_INPUT_OP_CALCULATE_WAIT_RESULT", "right"))} H960`, "success", 920, 1678, "handshake"),
    fsmEdge(`M${point(anchor("DISPLAY_AFTER_SECOND_OP", "bottom"))} V2190 H15 V990 H80`, "display accepts; enter next B", 430, 2177, "handshake"),
    fsmEdge(`M${point(anchor("COPY_A_TO_B", "bottom"))} V1380 H1600 V1690`, "automatic: calculate A op A", 1370, 1355),
    fsmEdge(`M${point(anchor("WAIT_SECOND_INPUT_AFTER_VALUE", "bottom", 100))} V1490 H1760 V1690`, "= after B", 2200, 1465, "key"),
    fsmEdge(`M${point(anchor("EQUAL_AFTER_SECOND_VALUE", "right"))} H1940`, "ALU accepts", 1900, 1678, "handshake"),
    fsmEdge(`M${point(anchor("EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT", "right"))} H2380`, "success", 2340, 1678, "handshake"),
    fsmEdge(`M${point(anchor("DISPLAY_AFTER_EQUAL", "right"))} H2820`, "display accepts result", 2780, 1678, "handshake"),

    fsmEdge(`M${point(anchor("WAIT_INPUT_AFTER_EQUAL", "bottom", -90))} V1900 H2660 V1950`, "NEG", 2770, 1875, "key"),
    fsmEdge(`M${point(anchor("INPUT_NEG_AFTER_EQUAL", "top", -100))} V1806`, "automatic: redisplay result", 2435, 1873, "auto", "end"),
    fsmEdge(`M${point(anchor("WAIT_INPUT_AFTER_EQUAL", "bottom"))} V1950`, "digit", 3020, 1875, "key", "start"),
    fsmEdge(`M${point(anchor("CLEAR_AFTER_EQUAL", "right"))} H3500 V115 H1580 V240`, "automatic: digit becomes new A", 2750, 102, "auto"),
    fsmEdge(`M${point(anchor("WAIT_INPUT_AFTER_EQUAL", "right", -24))} H3540 V460 H1260 V500`, "operator: continue from result", 2660, 447, "key"),
    fsmEdge(`M${point(anchor("WAIT_INPUT_AFTER_EQUAL", "right", 24))} H3570 V2190 H1680 V1806`, "= : repeat retained op and B", 2610, 2165, "key"),

    fsmEdge(`M${point(anchor("SECOND_INPUT_OP_CALCULATE_WAIT_RESULT", "bottom"))} V2350 H1780 V2460`, "division by zero", 1250, 2325, "error"),
    fsmEdge(`M${point(anchor("EQUAL_AFTER_SECOND_VALUE_WAIT_RESULT", "bottom"))} V2290 H1940 V2460`, "division by zero", 2200, 2265, "error"),
    fsmEdge(`M${point(anchor("DISPLAY_ERROR", "right"))} H2120`, "display accepts Err", 2080, 2448, "handshake"),
  ];

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="3650" height="2880" viewBox="0 0 3650 2880" role="img" aria-labelledby="title desc">
  <title id="title">Detailed calculator_core finite-state machine</title>
  <desc id="desc">All 25 RTL states with separated routing channels for key, handshake, automatic, and error transitions.</desc>
  ${fsmStyle()}
  <rect width="3650" height="2880" fill="#f8fafc"/>
  <text x="60" y="62" class="title">calculator_core FSM: detailed RTL transitions</text>
  <text x="60" y="98" class="subtitle">Every box is a named RTL state. Long return paths use dedicated routing channels outside the state rows.</text>
  <rect class="panel" x="55" y="185" width="2180" height="510" fill="#eff6ff"/><text x="75" y="220" class="lane-title">Clear and first-value entry</text>
  <rect class="panel" x="55" y="865" width="3075" height="545" fill="#fffbeb"/><text x="75" y="900" class="lane-title">Operator selected and second-value entry</text>
  <rect class="panel" x="55" y="1635" width="3325" height="500" fill="#f5f3ff"/><text x="75" y="1620" class="lane-title">ALU submission, result display, and after-equals actions</text>
  <rect class="panel" x="1655" y="2405" width="850" height="230" fill="#fef2f2"/><text x="1675" y="2440" class="lane-title">Division error</text>
  ${edges.join("\n")}
  ${stateNodes}
  <rect x="70" y="2800" width="3510" height="60" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="2"/>
  <line x1="100" y1="2830" x2="165" y2="2830" class="edge auto"/><text x="185" y="2836" class="legend">automatic</text>
  <line x1="420" y1="2830" x2="485" y2="2830" class="edge key"/><text x="505" y="2836" class="legend">button/key</text>
  <line x1="760" y1="2830" x2="825" y2="2830" class="edge handshake"/><text x="845" y="2836" class="legend">valid/ready or successful response</text>
  <line x1="1300" y1="2830" x2="1365" y2="2830" class="edge error"/><text x="1385" y="2836" class="legend">division by zero</text>
  <text x="1830" y="2836" class="note">AC from any input-wait state goes to AC; unhandled keys remain in that wait state.</text>
  </svg>`;
  fs.writeFileSync(path.join(outDir, "fsm-detailed.svg"), svg);
}

architectureSvg();
simplifiedFsmSvg();
detailedFsmSvg();
buttonArraySvg();
console.log("Wrote architecture.svg, button-array.svg, fsm-simplified.svg, and fsm-detailed.svg");
