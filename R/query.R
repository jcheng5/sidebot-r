library(openai)
library(here)

log <- function(...) {}
log <- message

api_key <- Sys.getenv("OPENAI_API_KEY", "")
if (!nzchar(api_key)) {
  stop("OPENAI_API_KEY environment variable is required")
}

client <- OpenAI()

system_prompt <- function(df, name, categorical_threshold = 10) {
  schema <- df_to_schema(df, name, categorical_threshold)

  # Read the prompt file
  prompt_path <- here("prompt.md")
  prompt_content <- readLines(prompt_path, warn = FALSE)
  prompt_text <- paste(prompt_content, collapse = "\n")

  # Replace the placeholder with the schema
  prompt_text <- gsub("\\$\\{SCHEMA\\}", schema, prompt_text, fixed = TRUE)

  # Return as a named list (equivalent to Python dict)
  return(list(role = "system", content = prompt_text))
}

df_to_schema <- function(df, name, categorical_threshold) {
  schema <- c(paste("Table:", name), "Columns:")

  column_info <- lapply(names(df), function(column) {
    # Map R classes to SQL-like types
    sql_type <- if (is.integer(df[[column]])) {
      "INTEGER"
    } else if (is.numeric(df[[column]])) {
      "FLOAT"
    } else if (is.logical(df[[column]])) {
      "BOOLEAN"
    } else if (inherits(df[[column]], "POSIXt")) {
      "DATETIME"
    } else {
      "TEXT"
    }

    info <- paste0("- ", column, " (", sql_type, ")")

    # For TEXT columns, check if they're categorical
    if (sql_type == "TEXT") {
      unique_values <- length(unique(df[[column]]))
      if (unique_values <= categorical_threshold) {
        categories <- unique(df[[column]])
        categories_str <- paste0("'", categories, "'", collapse = ", ")
        info <- c(info, paste0("  Categorical values: ", categories_str))
      }
    }

    return(info)
  })

  schema <- c(schema, unlist(column_info))
  return(paste(schema, collapse = "\n"))
}

query <- function(messages, model = "gpt-4o", ..., .ctx = NULL) {
  # TODO: Add tool call support
  # TODO: verify it's a good response

  while (TRUE) {
    # print(tail(messages, 1))
    completion <- client$chat$completions$create(
      model = model,
      messages = messages,
      temperature = 0.7,
      response_format = list(type = "json_object"),
      tools = tool_infos
    )

    msg <- completion$choices[[1]]$message
    if (!is.null(msg$tool_calls)) {
      log("Handling tool calls")
      # TODO: optionally return the tool calls to the caller as well
      messages <- c(messages, list(msg))
      tool_response_msgs <- lapply(msg$tool_calls, \(tool_call) {
        id <- tool_call$id
        type <- tool_call$type
        fname <- tool_call$`function`$name
        log("Calling ", fname)
        args <- jsonlite::parse_json(tool_call$`function`$arguments)
        func <- tool_funcs[[fname]]
        if (is.null(func)) {
          stop("Called unknown tool '", fname, "'")
        }
        if (".ctx" %in% names(formals(func))) {
          args$.ctx <- .ctx
        }
        result <- do.call(func, args)

        list(
          role = "tool",
          tool_call_id = id,
          name = fname,
          content = result
        )
      })
      messages <- c(messages, tool_response_msgs)
    } else {
      # TODO: We're assuming it's a response, we should double check
      break
    }
  }
  # print(completion$choices[[1]])
  completion
}

tools_env = new.env(parent = globalenv())
source(here("tools/tools.R"), local = tools_env)
tool_funcs <- as.list(tools_env)

tool_infos <- names(tool_funcs) |> lapply(\(fname) {
  jsonlite::read_json(here(paste0("tools/", fname, ".json")))
})