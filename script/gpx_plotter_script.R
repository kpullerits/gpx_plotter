library(plotKML)
library(ggmap)
library(tidyverse)
library(plotly)
library(htmlwidgets)
library(lubridate)
library(gganimate)

# Read input gpx -------------------------------------------------------

files = list.files(path = "./data_gpx", full.names = TRUE)
list_gpx <- list()
for (i in 1:length(files)) {
  list_gpx[[i]] <- readGPX(files[i])
}

df_list = vector("list", length(files))
for (i in 1:length(files)) {
  gpx <- list_gpx[[i]]$tracks[[1]][[1]] %>% 
    mutate(activity_id = names(list_gpx[[i]][["tracks"]][[1]]),
           filename = files[i],
           id = i)
  df_list[[i]] <- gpx
}
df <- as_tibble(data.table::rbindlist(df_list))

df <- df %>% 
  mutate(
    time = lubridate::as_datetime(time)
  )

# Find activity names and label -------------------------------------------

names_activities_input = c("Löpning", "Rullskidor", "Längdskidor", "Cykling", "Vandring")
names_activities_plot = c("Running", "Roller ski", "Cross country ski", "Cycling", "Hiking")

df <- df %>% 
  mutate(activity = NA)
for (i in 1:length(names_activities_input)) {
  df <- df %>% 
    mutate(activity = ifelse(str_detect(activity_id, names_activities_input[i]) & is.na(activity), 
                                    names_activities_plot[i],
                                    activity))
}

# Get background map ------------------------------------------------------

maptypes <- c("terrain",
            "terrain-background", "terrain-labels", "terrain-lines", "toner",
            "toner-2010", "toner-2011", "toner-background", "toner-hybrid",
            "toner-labels", "toner-lines", "toner-lite", "watercolor")
set_longitude = c(17.3, 18)
set_latitude = c(59.65, 60.05)

map <- get_stamenmap(
  bbox = c(left = set_longitude[1], right = set_longitude[2], 
           bottom = set_latitude[1], top = set_latitude[2]),
  maptype = maptypes[13],
  zoom = 12
)


# plot --------------------------------------------------------------------

set_alpha_val = 0.9
set_line_thick = 1

map_plot <- ggmap(map)+
  geom_path(
    data = df,
    aes(x = lon, y = lat, col = activity, group = id),
    size = set_line_thick,
    alpha = set_alpha_val)+
  coord_fixed(2)+
  scale_colour_brewer(palette = "Set1")+
  labs(x = "Longitude",
       y = "Latitude",
       title = "Sports activities in Uppsala 2021",
       color = "")+
  theme_minimal()

ggsave(map_plot, path = "output", filename = "map.pdf", device = "pdf", width = 12, height = 8)
ggsave(map_plot, path = "output", filename = "map.png", device = "png", width = 12, height = 8)

# plotly ------------------------------------------------------------------

df_plotly <- df %>%
  group_by(id) %>%
  mutate(start_time = min(time))

map_plot_plotly <- ggmap(map)+
  geom_path(
    data = df_plotly,
    aes(x = lon, y = lat, col = activity, group = id,
        text = paste0("Activity: ", activity, "\n", 
                      "Starttime: ", as_date(start_time))),
    size = set_line_thick,
    alpha = set_alpha_val
  )+
  scale_colour_brewer(palette = "Set1")+
  coord_fixed(2)+
  labs(x = "Longitude",
       y = "Latitude",
       title = "Sports activities in Uppsala 2021",
       color = "")+
  theme_minimal()

map_plot_plotly <- ggplotly(map_plot_plotly, tooltip=c("text")) %>%
  layout(xaxis = list(automargin=TRUE), yaxis = list(automargin=TRUE)
  )

result_path <- paste(getwd(), "/output/", sep = "")

ggplotly(map_plot_plotly, width = 12, height = 8, tooltip = "text", unit = "in") %>% 
  htmlwidgets::saveWidget(., paste(result_path, "map.html", sep=""))

# animation ---------------------------------------------------------------

# remove half points to save some time
df_animation <- df %>%
  group_by(id) %>% 
  filter(row_number() %% 2 == 1) %>% 
  ungroup()

# add NA after last point 
for (i in unique(df_animation$id)) {
  last_time_plus <- df_animation %>% 
    filter(id == i) %>% 
    filter(time == last(time)) %>% 
    mutate(lon = NA,
           lat = NA,
           time = time + 1)
  df_animation <- rbind(df_animation,last_time_plus)
}

# animate
df_animation <- df_animation %>% 
  arrange(time) %>% 
  mutate(timepoint = row_number())


p <- ggmap(map)+
  geom_path(
    data = df_animation,
    aes(x = lon, y = lat, col = activity, group = id),
    size = set_line_thick,
    alpha = set_alpha_val
  )+
  geom_point(
    data = df_animation,
    aes(x = lon, y = lat, col = activity, group = id, frame = id),
    size = 3,
    keep = FALSE
  )+
  scale_colour_brewer(palette = "Set1")+
  coord_fixed(2)+
  labs(x = "Longitude",
       y = "Latitude",
       title = "Sports activities in Uppsala 2021",
       color = "")+
  theme_minimal()

anim <- p + 
  transition_reveal(timepoint)+
  labs(title = "Date: {df_animation %>% filter(timepoint == frame_along) %>% pull(time) %>% as_date()}")

set_fps = 30
set_end_pause_time = 4 #seconds
set_end_pause_frames = set_end_pause_time * set_fps
set_duration = 24 #seconds

anim_save("./output/map.gif", animate(anim , end_pause = set_end_pause_frames, fps = set_fps, duration = set_duration,
                                      height = 8, width = 12, units = "in", res = 150))


save(
  df,
  names_activities_input,
  names_activities_plot,
  maptypes,
  set_latitude,
  set_longitude,
  map,
  map_plot,
  map_plot_plotly,
  file = "./output/data.Rdata"
)
