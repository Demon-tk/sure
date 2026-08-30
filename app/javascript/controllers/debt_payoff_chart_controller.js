import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import {
  createChartTooltip,
  CHART_TOOLTIP_CONTEXT_CLASSES,
  CHART_TOOLTIP_VALUE_CLASSES,
} from "utils/chart_tooltip";

// Debt payoff trajectory chart. One solid line per debt, each declining to
// zero at its payoff month. The whole curve is an already-run simulation, so
// there is no actual/projected split — every label and value arrives
// pre-formatted from DebtPayoffPlan#chart_payload.
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
    const series = data.series || [];
    if (series.length === 0) return;

    const width = root.clientWidth || 720;
    const height = root.clientHeight || 280;
    if (width <= 0 || height <= 0) return;

    const isDark = document.documentElement.getAttribute("data-theme") === "dark";
    const textSecondary = isDark ? "#cfcfcf" : "#737373";
    const borderSubdued = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.10)";

    const yAxisVisible = width >= 360;
    const margin = { top: 16, right: 24, bottom: 28, left: yAxisVisible ? 52 : 16 };
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    const maxMonth = d3.max(series, (s) => s.points.length - 1);
    const maxValue = d3.max(series, (s) => d3.max(s.points, (p) => p.value));

    const x = d3.scaleLinear().domain([0, maxMonth]).range([0, innerWidth]);
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

    // Axes: sparse month ticks labelled with the pre-formatted date of that
    // month's point; y-axis as compact currency.
    const tickMonths = x.ticks(Math.min(6, maxMonth));
    const monthLabel = (m) => {
      const point = series[0].points[Math.round(m)];
      return point ? point.date_formatted : "";
    };

    g.append("g")
      .attr("transform", `translate(0,${innerHeight})`)
      .call(
        d3
          .axisBottom(x)
          .tickValues(tickMonths)
          .tickSize(0)
          .tickPadding(10)
          .tickFormat(monthLabel),
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
            .tickFormat((v) => `${data.currency_symbol || ""}${d3.format("~s")(v)}`),
        )
        .call((axis) => axis.select(".domain").remove())
        .call((axis) => axis.selectAll("line").attr("stroke", borderSubdued))
        .call((axis) =>
          axis.selectAll("text").attr("fill", textSecondary).attr("font-size", "0.7rem"),
        );
    }

    const line = d3
      .line()
      .x((p) => x(p.month))
      .y((p) => y(p.value))
      .curve(d3.curveMonotoneX);

    series.forEach((s) => {
      g.append("path")
        .datum(s.points)
        .attr("fill", "none")
        .attr("stroke", s.color)
        .attr("stroke-width", 2)
        .attr("d", line);
    });

    // Hover: vertical crosshair snapped to the nearest month, tooltip lists
    // every debt's balance for that month.
    const tooltip = createChartTooltip(root);
    const crosshair = g
      .append("line")
      .attr("y1", 0)
      .attr("y2", innerHeight)
      .attr("stroke", borderSubdued)
      .attr("stroke-width", 1)
      .style("display", "none");

    svg
      .append("rect")
      .attr("x", margin.left)
      .attr("y", margin.top)
      .attr("width", innerWidth)
      .attr("height", innerHeight)
      .attr("fill", "transparent")
      .on("mousemove", (event) => {
        const [mx] = d3.pointer(event, g.node());
        const month = Math.round(x.invert(Math.max(0, Math.min(mx, innerWidth))));
        crosshair.attr("x1", x(month)).attr("x2", x(month)).style("display", null);

        const rows = series
          .map((s) => ({ series: s, point: s.points[month] }))
          .filter((r) => r.point)
          .map(
            (r) => `
              <div class="flex items-center gap-2">
                <span class="w-2 h-2 rounded-full shrink-0" style="background:${r.series.color}"></span>
                <span class="${CHART_TOOLTIP_CONTEXT_CLASSES} mb-0 flex-1">${r.series.name}</span>
                <span class="${CHART_TOOLTIP_VALUE_CLASSES}">${r.point.value_formatted}</span>
              </div>`,
          )
          .join("");
        const dateLabel = series[0].points[month]?.date_formatted || "";
        tooltip.innerHTML = `<div class="${CHART_TOOLTIP_CONTEXT_CLASSES}">${dateLabel}</div>${rows}`;
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
