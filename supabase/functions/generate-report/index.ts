import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { reportType, orgCode, dateStart, dateEnd, format } = await req.json();

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    let viewName = "";
    switch (reportType) {
      case "daily_worker_summary":
        viewName = "daily_worker_summary";
        break;
      case "machine_utilization":
        viewName = "machine_utilization_summary";
        break;
      case "production_efficiency":
        viewName = "production_efficiency_summary";
        break;
      case "exception_report":
        viewName = "exception_report";
        break;
      default:
        throw new Error("Invalid report type");
    }

    const { data, error } = await supabase
      .from(viewName)
      .select("*")
      .eq("organization_code", orgCode)
      .gte("date", dateStart)
      .lte("date", dateEnd);

    if (error) throw error;
    if (!data || data.length === 0) {
      return new Response(JSON.stringify({ message: "No data found" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    if (format === "json") {
      const filteredData = data.map((row: any) => {
        const { id, log_id, ...rest } = row;
        return rest;
      });
      return new Response(JSON.stringify(filteredData), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }

    // Generate CSV (default)
    const headers = Object.keys(data[0]).filter(
      (h) => h !== "id" && h !== "log_id"
    );
    const csvContent = [
      headers.map((h) => h.replaceAll("_", " ").toUpperCase()).join(","),
      ...data.map((row) =>
        headers
          .map((header) => {
            const val = row[header];
            if (val === null || val === undefined) return "";
            const str = val.toString();
            return str.includes(",") ? `"${str.replace(/"/g, '""')}"` : str;
          })
          .join(",")
      ),
    ].join("\n");

    return new Response(csvContent, {
      headers: {
        ...corsHeaders,
        "Content-Type": "text/csv",
        "Content-Disposition": `attachment; filename="${reportType}_${dateStart}_${dateEnd}.csv"`,
      },
      status: 200,
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }
});
