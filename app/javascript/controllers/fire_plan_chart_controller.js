import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import {
  createChartTooltip,
  CHART_TOOLTIP_CONTEXT_CLASSES,
  CHART_TOOLTIP_VALUE_CLASSES,
} from "utils/chart_tooltip";

// FIRE projection chart. A single deterministic portfolio line drawn over the
// Monte Carlo p10–p90 band, with the FIRE number as a horizontal threshold and
// the first FIRE-eligible year as a vertical marker. Every label arrives
// pre-formatted from FirePlan#chart_payload.
const PORTFOLIO_COLOR = "#3B82F6";

export default class extends Controller {
  static values = {
    data: Object,
    ariaLabel: String,
    ariaDescription: String,
  };

  connect() {
    this._resize = this._draw.bind(this);
    window.addEventListener("resize", this._resize);
    // Container may have 0 width on initial connect (Turbo restoration,
    // hidden parent). First observer callback performs the initial paint.
    if (typeof ResizeObserver !== "undefined") {
      this._observer = new ResizeObserver(() => this._draw());
      this._observer.observe(this.element);
    } else {
      this._draw();
    }
    // Repaint on theme toggle: SVG attributes bake light/dark values at
    // draw time.
    if (typeof MutationObserver !== "undefined") {
      this._themeObserver = new MutationObserver((mutations) => {
        if (mutations.some((m) => m.attributeName === "data-theme")) this._draw();
      });
      this._themeObserver.observe(document.documentElement, {
        attributes: true,
        attributeFilter: ["data-theme"],
      });
    }
    this._onTurboRender = () => {
      if (!this.element.querySelector("svg")) this._draw();
    };
    document.addEventListener("turbo:render", this._onTurboRender);
    document.addEventListener("turbo:frame-load", this._onTurboRender);
  }

  disconnect() {
    window.removeEventListener("resize", this._resize);
    this._observer?.disconnect();
    this._themeObserver?.disconnect();
    if (this._onTurboRender) {
      document.removeEventListener("turbo:render", this._onTurboRender);
      document.removeEventListener("turbo:frame-load", this._onTurboRender);
    }
  }

  _draw() {
    const root = this.element;
    root.innerHTML = "";

    const data = this.dataValue || {};
    const rows = data.rows || [];
    // Optional "without your milestones" series, [{year, value}] or null.
    const baseline = data.baseline || [];
    if (rows.length === 0) return;

    const width = root.clientWidth || 720;
    const height = root.clientHeight || 300;
    if (width <= 0 || height <= 0) return;

    const isDark = document.documentElement.getAttribute("data-theme") === "dark";
    const textSecondary = isDark ? "#cfcfcf" : "#737373";
    const borderSubdued = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.10)";

    const yAxisVisible = width >= 360;
    const margin = { top: 16, right: 24, bottom: 28, left: yAxisVisible ? 52 : 16 };
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    const symbol = data.currency_symbol || "";
    const bandRows = rows.filter((r) => r.p10 != null && r.p90 != null);
    // The band's upper edge usually overshoots the deterministic line, so the
    // domain has to clear whichever is taller.
    const maxValue = d3.max(rows.concat(baseline), (r) => Math.max(r.value, r.p90 ?? 0));

    const x = d3
      .scaleLinear()
      .domain(d3.extent(rows, (r) => r.year))
      .range([0, innerWidth]);
    const y = d3
      .scaleLinear()
      .domain([0, maxValue * 1.05])
      .range([innerHeight, 0]);

    const svg = d3
      .select(root)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("role", "img")
      .attr("aria-label", this.ariaLabelValue || null);
    if (this.ariaDescriptionValue) {
      svg.append("desc").text(this.ariaDescriptionValue);
    }

    const g = svg
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`);

    // Axes: sparse year ticks; y-axis as compact currency.
    g.append("g")
      .attr("transform", `translate(0,${innerHeight})`)
      .call(
        d3
          .axisBottom(x)
          .ticks(6)
          .tickSize(0)
          .tickPadding(10)
          .tickFormat(d3.format("d")),
      )
      .call((axis) => axis.select(".domain").attr("stroke", borderSubdued))
      .call((axis) =>
        axis.selectAll("text").attr("fill", textSecondary).attr("font-size", "0.7rem"),
      );

    if (yAxisVisible) {
      g.append("g")
        .call(
          d3
            .axisLeft(y)
            .ticks(4)
            .tickSize(-innerWidth)
            .tickPadding(8)
            .tickFormat((v) => `${symbol}${d3.format("~s")(v)}`),
        )
        .call((axis) => axis.select(".domain").remove())
        .call((axis) => axis.selectAll("line").attr("stroke", borderSubdued))
        .call((axis) =>
          axis.selectAll("text").attr("fill", textSecondary).attr("font-size", "0.7rem"),
        );
    }

    // "Without your milestones" baseline, under the main series.
    if (baseline.length > 1) {
      const baselineLine = d3
        .line()
        .x((r) => x(r.year))
        .y((r) => y(r.value))
        .curve(d3.curveMonotoneX);

      g.append("path")
        .datum(baseline)
        .attr("fill", "none")
        .attr("stroke", textSecondary)
        .attr("stroke-width", 1.5)
        .attr("stroke-dasharray", "4 4")
        .attr("d", baselineLine);
    }

    // Monte Carlo p10–p90 band, under the deterministic line.
    if (bandRows.length > 1) {
      const area = d3
        .area()
        .x((r) => x(r.year))
        .y0((r) => y(r.p10))
        .y1((r) => y(r.p90))
        .curve(d3.curveMonotoneX);

      g.append("path")
        .datum(bandRows)
        .attr("fill", PORTFOLIO_COLOR)
        .attr("fill-opacity", 0.15)
        .attr("stroke", "none")
        .attr("d", area);
    }

    const line = d3
      .line()
      .x((r) => x(r.year))
      .y((r) => y(r.value))
      .curve(d3.curveMonotoneX);

    g.append("path")
      .datum(rows)
      .attr("fill", "none")
      .attr("stroke", PORTFOLIO_COLOR)
      .attr("stroke-width", 2)
      .attr("d", line);

    // FIRE number threshold, labelled at the right edge.
    if (data.fire_number > 0 && data.fire_number <= y.domain()[1]) {
      const fireY = y(data.fire_number);
      g.append("line")
        .attr("x1", 0)
        .attr("x2", innerWidth)
        .attr("y1", fireY)
        .attr("y2", fireY)
        .attr("stroke", textSecondary)
        .attr("stroke-width", 1)
        .attr("stroke-dasharray", "4 4");
      g.append("text")
        .attr("x", innerWidth)
        .attr("y", fireY - 6)
        .attr("text-anchor", "end")
        .attr("fill", textSecondary)
        .attr("font-size", "0.7rem")
        .text(data.fire_number_label || "");
    }

    // Vertical marker at the first year the plan reaches FIRE.
    const firedRow = rows.find((r) => r.fired);
    if (firedRow) {
      g.append("line")
        .attr("x1", x(firedRow.year))
        .attr("x2", x(firedRow.year))
        .attr("y1", 0)
        .attr("y2", innerHeight)
        .attr("stroke", textSecondary)
        .attr("stroke-width", 1)
        .attr("stroke-dasharray", "4 4");
    }

    // Hover: vertical crosshair snapped to the nearest year, tooltip shows the
    // deterministic value plus that year's percentile band.
    const tooltip = createChartTooltip(root);
    const crosshair = g
      .append("line")
      .attr("y1", 0)
      .attr("y2", innerHeight)
      .attr("stroke", borderSubdued)
      .attr("stroke-width", 1)
      .style("display", "none");

    const plain = d3.format(",.0f");
    const firstYear = rows[0].year;

    svg
      .append("rect")
      .attr("x", margin.left)
      .attr("y", margin.top)
      .attr("width", innerWidth)
      .attr("height", innerHeight)
      .attr("fill", "transparent")
      .on("mousemove", (event) => {
        const [mx] = d3.pointer(event, g.node());
        const year = Math.round(x.invert(Math.max(0, Math.min(mx, innerWidth))));
        const row = rows[Math.max(0, Math.min(year - firstYear, rows.length - 1))];
        if (!row) return;

        crosshair
          .attr("x1", x(row.year))
          .attr("x2", x(row.year))
          .style("display", null);

        const band =
          row.p10 != null && row.p90 != null
            ? `
              <div class="flex items-center gap-2">
                <span class="${CHART_TOOLTIP_CONTEXT_CLASSES} mb-0 flex-1">p10 – p90</span>
                <span class="${CHART_TOOLTIP_VALUE_CLASSES}">${symbol}${plain(row.p10)} – ${symbol}${plain(row.p90)}</span>
              </div>`
            : "";

        tooltip.innerHTML = `<div class="${CHART_TOOLTIP_CONTEXT_CLASSES}">${row.year} · ${row.age}</div>
              <div class="flex items-center gap-2">
                <span class="w-2 h-2 rounded-full shrink-0" style="background:${PORTFOLIO_COLOR}"></span>
                <span class="${CHART_TOOLTIP_VALUE_CLASSES} flex-1">${row.value_formatted}</span>
              </div>${band}`;
        tooltip.style.display = "block";

        const rootRect = root.getBoundingClientRect();
        const tipWidth = tooltip.offsetWidth;
        let left = event.clientX - rootRect.left + 12;
        if (left + tipWidth > rootRect.width) left = left - tipWidth - 24;
        tooltip.style.left = `${Math.max(0, left)}px`;
        tooltip.style.top = `${event.clientY - rootRect.top + 12}px`;
      })
      .on("mouseleave", () => {
        crosshair.style("display", "none");
        tooltip.style.display = "none";
      });
  }
}
