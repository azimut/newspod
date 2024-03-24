port module Main exposing (..)

import Browser
import Dict exposing (Dict)
import Html exposing (Html, a, article, details, div, footer, header, input, main_, span, summary, text, time)
import Html.Attributes exposing (class, href, placeholder, value)
import Html.Events exposing (onClick, onInput)
import Loaders
import String exposing (fromInt)


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


type alias Model =
    { feeds : List Feed
    , entries : Dict Int (List Entry)
    , search : String
    }


type alias Feed =
    { id : Int
    , title : String
    , description : String
    , isVisible : Bool
    , isSelected : Bool
    , nEntries : Int
    }


type alias Entry =
    { id : Int
    , feedid : Int
    , title : String
    , date : String
    , url : String
    , description : String
    , content : String
    , isVisible : Bool
    }


type Msg
    = InitFeeds (List InitFeed)
    | AskForEntries Int
    | NewEntries (List NewEntry)
    | NewInput String


type alias InitFeed =
    { id : Int
    , title : String
    , nEntries : Int
    }


type alias NewEntry =
    { id : Int
    , feedid : Int
    , title : String
    , date : String
    , url : String
    }


port askForEntries : Int -> Cmd msg


port receiveEntries : (List NewEntry -> msg) -> Sub msg


port receiveInitFeeds : (List InitFeed -> msg) -> Sub msg


init : flags -> ( Model, Cmd msg )
init _ =
    ( Model [] Dict.empty "", Cmd.none )


newEntry : NewEntry -> Entry
newEntry { id, feedid, title, date, url } =
    { id = id
    , feedid = feedid
    , title = title
    , date = date
    , url = url
    , description = ""
    , content = ""
    , isVisible = True
    }


newEntries : Model -> List NewEntry -> Model
newEntries ({ entries } as model) nes =
    case nes of
        [] ->
            model

        entry :: _ ->
            { model | entries = Dict.insert entry.feedid (List.map newEntry nes) entries }


initFeed : InitFeed -> Feed
initFeed { id, title, nEntries } =
    { id = id, title = title, description = "", isVisible = True, isSelected = False, nEntries = nEntries }


update : Msg -> Model -> ( Model, Cmd msg )
update msg ({ entries } as model) =
    case msg of
        NewInput s ->
            ( { model | search = s }, Cmd.none )

        AskForEntries feedid ->
            case Dict.get feedid entries of
                Nothing ->
                    ( selectFeed model feedid, askForEntries feedid )

                Just _ ->
                    ( selectFeed model feedid, Cmd.none )

        InitFeeds iFeeds ->
            ( Model (List.map initFeed iFeeds) Dict.empty ""
            , Cmd.none
            )

        NewEntries es ->
            ( newEntries model es, Cmd.none )


selectFeed : Model -> Int -> Model
selectFeed ({ feeds } as model) feedid =
    { model
        | feeds =
            List.map
                (\feed ->
                    if feed.id == feedid then
                        { feed | isSelected = not feed.isSelected }

                    else
                        feed
                )
                feeds
    }


viewFeed : Feed -> Dict Int (List Entry) -> Html Msg
viewFeed { title, id, nEntries, isSelected } entries =
    article
        [ onClick (AskForEntries id) ]
        [ details [] <|
            summary
                [ if isSelected then
                    class "selected"

                  else
                    class ""
                ]
                [ text (title ++ " [" ++ fromInt nEntries ++ "]") ]
                :: (viewEntries <|
                        Maybe.withDefault []
                            (Dict.get id entries)
                   )
        ]


viewEntry : Entry -> Html Msg
viewEntry { title, date, url } =
    div [ class "episode" ]
        [ div [ class "episode-title" ]
            [ text title ]
        , div [ class "episode-date" ]
            [ a [ href url ]
                [ time [] [ text date ] ]
            ]
        ]


viewEntries : List Entry -> List (Html Msg)
viewEntries entries =
    List.map viewEntry entries


view : Model -> Html Msg
view { feeds, entries, search } =
    case feeds of
        [] ->
            div [ class "loader" ]
                [ Loaders.ballTriangle 150 "#fff" ]

        _ ->
            div []
                [ header []
                    [ text "news"
                    , span [ class "pod" ] [ text "pod" ]
                    , input [ placeholder "search", value search, onInput NewInput ] []
                    ]
                , main_ [] <|
                    List.map (\feed -> viewFeed feed entries) feeds
                , footer []
                    [ div []
                        [ a [ href "https://github.com/azimut/newspod" ]
                            [ text "source code" ]
                        ]
                    ]
                ]


subscriptions : model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ receiveInitFeeds InitFeeds
        , receiveEntries NewEntries
        ]
