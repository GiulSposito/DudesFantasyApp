// Projection Lab — full build in M7. M2 stub.
import * as data from "../data.js";
import { el, table } from "../app.js";
import * as fmt from "../format.js";

export async function render(root) {
  const rows = await data.q(
    "SELECT data_src, position, avg(mae) AS mae, avg(bias) AS bias, sum(n) AS n " +
    "FROM source_accuracy GROUP BY data_src, position ORDER BY data_src, position",
    "source_accuracy",
  );
  root.replaceChildren(
    el("p", { class: "text-muted" }, "M2 stub — accuracy heatmap and source dot plot land in M7."),
    table(rows, [
      { key: "data_src", label: "Source" },
      { key: "position", label: "Pos" },
      { key: "mae", label: "MAE", fmt: (v) => fmt.points(v, 2) },
      { key: "bias", label: "Bias", fmt: (v) => fmt.points(v, 2) },
      { key: "n", label: "N" },
    ]),
  );
}
