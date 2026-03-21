# Deploy to Posit Connect
#
# OPENAI_API_KEY must be set in the current R session (e.g. via .Renviron).
# It will be securely sent to the server via envVars.
#
# python is required for reticulate (used by plotly's save_image/kaleido).
# requirements.txt lists the needed Python packages (plotly, kaleido).
rsconnect::deployApp(
  appDir = ".",
  account = "carson",
  server = "connect.posit.it",
  envVars = c("OPENAI_API_KEY"),
  python = "/opt/homebrew/bin/python3"
)
