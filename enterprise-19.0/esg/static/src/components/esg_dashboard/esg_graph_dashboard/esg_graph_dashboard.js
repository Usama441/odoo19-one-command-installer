import { Component, onMounted, onWillStart, onWillUnmount, useRef } from "@odoo/owl";
import { loadJS } from "@web/core/assets";

export class EsgGraphDashboard extends Component {
    static template = "esg.GraphDashboard";
    static props = {
        config: {
            type: Object,
        },
    };

    setup() {
        this.canvasRef = useRef("canvas");
        onWillStart(() => loadJS("/web/static/lib/Chart/Chart.js"));
        onMounted(() => {
            this.renderChart();
        });
        onWillUnmount(() => {
            if (this.chart) {
                this.chart.destroy();
            }
        });
    }

    renderChart() {
        this.chart = new Chart(this.canvasRef.el, this.props.config);
    }
}
