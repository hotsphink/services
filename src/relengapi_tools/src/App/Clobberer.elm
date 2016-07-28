module App.Clobberer exposing (..)

import Dict exposing ( Dict )
import Focus exposing ( set, create, Focus, (=>) )
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed
import Http
import Json.Decode as JsonDecode exposing ( (:=) )
import Json.Encode as JsonEncode
import RemoteData as RemoteData exposing ( WebData, RemoteData(..) )
import RouteUrl.Builder exposing ( Builder, builder, replacePath )
import Task exposing ( Task )

import App.Utils exposing (..)


-- TYPES

type alias BackendItem =
    { name : String
    , data : Dict String (List String)
    }

type alias BackendData = List BackendItem

type alias ModelBackend =
    { title : String
    , data : WebData BackendData
    , clobber : WebData BackendData
    , clobber_messages : List (String, String)
    , selected_dropdown : Maybe String
    , selected : Dict String (List String)
    , selected_details : Bool
    }

type alias Model =
    { baseUrl : String
    , buildbot : ModelBackend
    , taskcluster : ModelBackend
    }

type Backend
    = BuildbotBackend
    | TaskclusterBackend


type Msg
    = Clobber Backend
    | Clobbered Backend (WebData BackendData)
    | FetchData Backend
    | DataFetched Backend (WebData BackendData)
    | SelectDropdown Backend String
    | AddSelected Backend String String
    | RemoveSelected Backend String String
    | ToggleSelectedDetails Backend
    | SelectAll Backend String
    | SelectNone Backend String


-- API



viewClobberButton backend model = 
    let
        buttonNumber = List.length <| List.concat <| Dict.values model.selected
        buttonText = "Submit clobberer (" ++ (toString buttonNumber) ++ ")"
        buttonDisabled = if buttonNumber == 0 then True else False
    in
        button [ class "btn btn-primary btn-large"
               , disabled buttonDisabled
               , App.Utils.onClick <| Clobber backend
               ]
               [ text buttonText ]
        --  <button className="btn btn-primary btn-large"
        --          onClick={props.clobber(props.table_selected)}
        --  </button>


viewClobberDetails backend model =
    let
        (buttonText, itemText, backendName) = case backend of
            TaskclusterBackend -> 
                ("worker type(s)", "Worker Type: ", "taskcluster")
            BuildbotBackend ->
                ("builder(s)", "Builder: ", "buildbot")
        button = a [ href <| "#clobber-selected-" ++ backendName
                   , attribute "data-toggle" "collapse"
                   , attribute "aria-expanded" "false"
                   , attribute "aria-controls" "collapseExample"
                   , App.Utils.onClick <| ToggleSelectedDetails backend
                   ]
                   [ text <| "Show/Hide selected " ++ buttonText ++ " to be clobbered" ]
        collapsed = if model.selected_details == True then " in" else ""
        items'' key value =
            li []
               [ div [] [ b [] [ text "Branch: " ]
                        , text key
                        ]
               , div [] [ b [] [ text itemText ]
                        , text value
                        ]
               ]
        items' (key, value) = List.map (items'' key) value
        items = List.concat <| List.map items' <| Dict.toList model.selected
    in
       if items == []
          then []
          else [ button
               , ul [ id <| "#clobber-selected-" ++ backendName
                    , class <| "collapse" ++ collapsed
                    ] items
               ]


viewBackend : Backend -> ModelBackend -> Html Msg
viewBackend backend model =
    div []
        [ viewClobberButton backend model
        , div [ class "clobberer-submit-description" ] <| viewClobberDetails backend model
        , ( case model.data of
                Success data ->
                    dropdown (SelectDropdown backend) data model.selected_dropdown
                Failure message ->
                    div [] [ error (FetchData backend) (toString message) ]
                Loading ->
                    div [] [ loading ]
                NotAsked ->
                    div [] []
          )

        , ( case model.selected_dropdown of
                Nothing ->
                    div [] []
                Just selected_dropdown ->
                    table [ class "table table-hover" ]
                          [ thead []
                                  [ tr []
                                       [ th []
                                            [ input [ type' "checkbox"
                                                    , onCheck (\checked -> case checked of
                                                                                True -> SelectAll backend selected_dropdown
                                                                                False -> SelectNone backend selected_dropdown
                                                              )
                                                    , checked
                                                        ( let
                                                             data = case model.data of
                                                                 Success data -> data
                                                                 _ -> []
                                                             all = Dict.keys
                                                                 <| Maybe.withDefault Dict.empty
                                                                 <| Dict.get selected_dropdown
                                                                 <| Dict.fromList (List.map (\x -> (x.name, x.data)) data)
                                                             current = Maybe.withDefault []
                                                                 <| Dict.get selected_dropdown model.selected
                                                          in
                                                             if current == all && current /= []
                                                                then True
                                                                else False
                                                        )
                                                    ] []
                                            ]
                                       , th []
                                            [ text ( case backend of
                                                         TaskclusterBackend -> 
                                                             "Worker Type"
                                                         BuildbotBackend ->
                                                             "Builder"
                                                   )
                                            ]
                                       , th []
                                            [ text ( case backend of
                                                         TaskclusterBackend -> 
                                                             "Caches"
                                                         BuildbotBackend ->
                                                             "Last clobber"
                                                   )
                                            ]
                                       ]
                                  ]
                          , Html.Keyed.node "tbody" []
                            ( let
                                  data = case model.data of
                                      Success data -> data
                                      _ -> []
                                  items' = Dict.get selected_dropdown <| Dict.fromList (List.map (\x -> (x.name, x.data)) data)
                              in
                                 case items' of
                                     Nothing -> []
                                     Just items ->
                                         Dict.values <| Dict.map
                                             (\k v ->
                                                 ( k 
                                                 , tr []
                                                      [ td []
                                                           [ input [ type' "checkbox"
                                                                   , onCheck
                                                                       (\checked ->
                                                                           case checked of
                                                                               True -> AddSelected backend selected_dropdown k
                                                                               False -> RemoveSelected backend selected_dropdown k
                                                                       )
                                                                   , checked (
                                                                       case Dict.get selected_dropdown model.selected of
                                                                         Just itemz -> List.member k itemz
                                                                         Nothing -> False
                                                                     )
                                                                   ] []
                                                           ]
                                                      , td []
                                                           [ text k ]
                                                      , td []
                                                           [ ul [] <| List.map (\x -> li [] [ text x ]) v
                                                           ]
                                                      ]
                                                 )
                                             )
                                             items
                            )
                          ]
          )
        ]


view : Model -> Html Msg
view model =
    div []
        [ h1 [] [ text "Clobberer" ]
        , p [] [ text "A repairer of buildbot builders and taskcluster worker types." ]
        , p [] [ text "TODO: link to documentation" ]
        , div [ class "row" ]
              [ div [ class "col-md-6" ]
                    [ h2 [] [ text "Taskcluster" ]
                    , viewBackend TaskclusterBackend model.taskcluster
                    ]
              , div [ class "col-md-6" ]
                    [ h2 [] [ text "Buildbot" ]
                    , viewBackend BuildbotBackend model.buildbot
                    ]
              ]
        ]


initBackend : String -> ModelBackend
initBackend title  =
    { title = title
    , data = NotAsked
    , clobber = NotAsked
    , clobber_messages = []
    , selected_dropdown = Nothing
    , selected = Dict.empty
    , selected_details = False
    }

init : Model
init =
    { buildbot = initBackend "Buildbot"
    , taskcluster = initBackend "Taskcluster"
    , baseUrl = "data-clobberer-url not set"
    }

initPage : String -> Model -> (Model, Cmd Msg)
initPage baseUrl model =
    ( { buildbot = initBackend "Buildbot"
      , taskcluster = initBackend "Taskcluster"
      , baseUrl = baseUrl
      }
    , Cmd.batch [ fetchBackend (DataFetched BuildbotBackend) (baseUrl ++ "/buildbot")
                --XXX, fetchBackend (DataFetched TaskclusterBackend) (baseUrl ++ "/taskcluster")
                ]
    )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        Clobber backend ->
            let
                encodeBody key items = 
                    (key, JsonEncode.list items)
                (newModel, backendUrl, body) = case backend of
                    TaskclusterBackend ->
                        ( set (taskcluster => clobber) Loading model
                        , model.baseUrl ++ "/taskcluster"
                        , Http.empty
                        -- TODO
                        --, Body.BodyString 
                        --    <| JsonEncode.encode 0
                        --    <| JsonEncode.object [] 
                        --    <| List.map encodeBody
                        --    <| Dict.toList model.taskcluster.selected
                        )
                    BuildbotBackend ->
                        ( set (buildbot => clobber) Loading model
                        , model.baseUrl ++ "/buildbot"
                        , Http.empty
                        -- TODO
                        --, Body.BodyString 
                        --    <| JsonEncode.encode 0
                        --    <| JsonEncode.object [] 
                        --    <| List.map encodeBody
                        --    <| Dict.toList model.buildout.selected
                        )
            in
                (newModel, clobberBackend (Clobbered backend) backendUrl body)
        Clobbered backend newData ->
            let
                -- TODO from newData set clobber_message
                newModel = case backend of
                    TaskclusterBackend ->
                        set (taskcluster => clobber) NotAsked model
                    BuildbotBackend ->
                        set (buildbot => clobber) NotAsked model
            in
                ( newModel, Cmd.none )
        FetchData backend ->
            let
                (newModel, backendUrl) = case backend of
                    TaskclusterBackend ->
                        ( set (taskcluster => data) Loading model
                        , model.baseUrl ++ "/taskcluster"
                        )
                    BuildbotBackend ->
                        ( set (buildbot => data) Loading model
                        , model.baseUrl ++ "/buildbot"
                        )
            in
                (newModel, fetchBackend (DataFetched backend) backendUrl )
        DataFetched backend newData ->
            let
                newModel = case backend of
                    TaskclusterBackend ->
                        set (taskcluster => data) newData model
                    BuildbotBackend ->
                        set (buildbot => data) newData model
            in
                ( newModel, Cmd.none )
        SelectDropdown backend name ->
            let
                newModel = case backend of
                    TaskclusterBackend ->
                        set (taskcluster => selected_dropdown) (Just name) model
                    BuildbotBackend ->
                        set (buildbot => selected_dropdown) (Just name) model
            in
                ( newModel, Cmd.none )
        AddSelected backend key value ->
            let
                newModel = case backend of
                    TaskclusterBackend ->
                        let
                            selected' = Dict.insert key values' model.taskcluster.selected
                            values' = if List.member value values
                                      then values
                                      else (value :: values)
                            values = Maybe.withDefault []
                                <| Dict.get key model.taskcluster.selected
                        in
                            set (taskcluster => selected) selected' model
                    BuildbotBackend ->
                        let
                            selected' = Dict.insert key values' model.buildbot.selected
                            values' = if List.member value values
                                      then values
                                      else (value :: values)
                            values = Maybe.withDefault []
                                <| Dict.get key model.buildbot.selected
                        in
                            set (buildbot => selected) selected' model
            in
                ( newModel, Cmd.none )
        RemoveSelected backend key value ->
            let
                newModel = case backend of
                    TaskclusterBackend ->
                        let
                            selected' = Dict.insert key values' model.taskcluster.selected
                            values' = List.filter (\x -> x /= value) values
                            values = Maybe.withDefault []
                                <| Dict.get key model.taskcluster.selected
                        in
                            set (taskcluster => selected) selected' model
                    BuildbotBackend ->
                        let
                            selected' = Dict.insert key values' model.buildbot.selected
                            values' = List.filter (\x -> x /= value) values
                            values = Maybe.withDefault []
                                <| Dict.get key model.buildbot.selected
                        in
                            set (buildbot => selected) selected' model
            in
                ( newModel, Cmd.none )
        ToggleSelectedDetails backend ->
            let
                newModel = case backend of
                    TaskclusterBackend ->
                        let
                            toggled_selected_details = not model.taskcluster.selected_details
                        in
                            set (taskcluster => selected_details) toggled_selected_details model
                    BuildbotBackend ->
                        let
                            toggled_selected_details = not model.buildbot.selected_details
                        in
                            set (buildbot => selected_details) toggled_selected_details model
            in
                ( newModel, Cmd.none )
        SelectAll backend selected_dropdown ->
            let
                newModel = case backend of
                    TaskclusterBackend ->
                        let
                            data = case model.taskcluster.data of
                                Success data -> data
                                _ -> []
                            all = Dict.keys
                                <| Maybe.withDefault Dict.empty
                                <| Dict.get selected_dropdown
                                <| Dict.fromList (List.map (\x -> (x.name, x.data)) data)
                            newSelected = Dict.insert selected_dropdown all model.taskcluster.selected
                        in
                            set (taskcluster => selected) newSelected model
                    BuildbotBackend ->
                        let
                            data = case model.buildbot.data of
                                Success data -> data
                                _ -> []
                            all = Dict.keys
                                <| Maybe.withDefault Dict.empty
                                <| Dict.get selected_dropdown
                                <| Dict.fromList (List.map (\x -> (x.name, x.data)) data)
                            newSelected = Dict.insert selected_dropdown all model.buildbot.selected
                        in
                            set (buildbot => selected) newSelected model
            in
                ( newModel, Cmd.none )
        SelectNone backend selected_dropdown ->
            let
                newModel = case backend of
                    TaskclusterBackend ->
                        let
                            newSelected = Dict.insert selected_dropdown [] model.taskcluster.selected
                        in
                            set (taskcluster => selected) newSelected model
                    BuildbotBackend ->
                        let
                            newSelected = Dict.insert selected_dropdown [] model.buildbot.selected
                        in
                            set (buildbot => selected) newSelected model
            in
                ( newModel, Cmd.none )



-- IMPLEMENTATION


buildbot : Focus { record | buildbot : a } a
buildbot = create .buildbot (\f r -> { r | buildbot = f r.buildbot })

taskcluster : Focus { record | taskcluster : a } a
taskcluster = create .taskcluster (\f r -> { r | taskcluster = f r.taskcluster })

data : Focus { record | data : a } a
data = create .data (\f r -> { r | data = f r.data })

clobber : Focus { record | clobber : a } a
clobber = create .clobber (\f r -> { r | clobber = f r.clobber })

selected_dropdown : Focus { record | selected_dropdown : a } a
selected_dropdown  = create .selected_dropdown (\f r -> { r | selected_dropdown = f r.selected_dropdown })

selected : Focus { record | selected : a } a
selected = create .selected (\f r -> { r | selected = f r.selected })

selected_details: Focus { record | selected_details: a } a
selected_details= create .selected_details (\f r -> { r | selected_details = f r.selected_details })


decodeData : JsonDecode.Decoder (List BackendItem)
decodeData =
    JsonDecode.at [ "result" ]
       ( JsonDecode.list
           ( JsonDecode.object2 BackendItem
                                ( "name" := JsonDecode.string )
                                ( "data" := JsonDecode.dict (JsonDecode.list JsonDecode.string) )
           )
       )

fetchBackend : (WebData BackendData -> Msg) -> String -> Cmd Msg
fetchBackend afterMsg url =
   getJson decodeData url
        |> RemoteData.asCmd
        |> Cmd.map afterMsg

clobberBackend : (WebData BackendData -> Msg)  -> String -> Http.Body -> Cmd Msg
clobberBackend afterMsg url body =
   postJson decodeData url body
        |> RemoteData.asCmd
        |> Cmd.map afterMsg



-- UTILS



-- XXX: this should work but header is never sent

getJson : JsonDecode.Decoder value -> String -> Task Http.Error value
getJson decoder url =
  let request =
        { verb = "GET"
        , headers = [( "Accept", "application/json" )]
        , url = url
        , body = Http.empty
        }
  in
    Http.fromJson decoder
        (Http.send Http.defaultSettings request)

postJson : JsonDecode.Decoder value -> String -> Http.Body -> Task Http.Error value
postJson decoder url body =
  let request =
        { verb = "POST"
        , headers = [( "Accept", "application/json" )]
        , url = url
        , body = body
        }
  in
    Http.fromJson decoder
        (Http.send Http.defaultSettings request)
