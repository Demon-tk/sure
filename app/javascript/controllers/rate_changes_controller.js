import { Controller } from "@hotwired/stimulus";

// Add/remove scheduled rate-change rows on a liability form. Rows are plain
// array params (rate_changes[][effective_on] / [rate]); the model setter
// drops blank rows, so removal client-side is a convenience, not a contract.
export default class extends Controller {
  static targets = ["list", "template"];

  add() {
    this.listTarget.insertAdjacentHTML(
      "beforeend",
      this.templateTarget.innerHTML,
    );
  }

  remove(event) {
    event.target.closest("[data-rate-changes-row]").remove();
  }
}
