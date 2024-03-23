port module Main exposing (..)

import Browser
import Dict exposing (Dict)
import Html exposing (Html, article, details, div, summary, text)
import Html.Events exposing (onClick)


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
    }


type alias Feed =
    { id : Int
    , title : String
    , description : String
    , isVisible : Bool
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


type alias InitFeed =
    { id : Int
    , title : String
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
    ( Model [] Dict.empty, Cmd.none )


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


initFeeds : List InitFeed -> Model
initFeeds ifs =
    { feeds = List.map initFeed ifs
    , entries = Dict.empty
    }


initFeed : InitFeed -> Feed
initFeed { id, title } =
    { id = id, title = title, description = "", isVisible = True }


update : Msg -> Model -> ( Model, Cmd msg )
update msg model =
    case msg of
        AskForEntries feedid ->
            ( model, askForEntries feedid )

        InitFeeds feeds ->
            ( initFeeds feeds, Cmd.none )

        NewEntries entries ->
            ( newEntries model entries, Cmd.none )


feedView : Feed -> Html Msg
feedView { title, id } =
    article [ onClick (AskForEntries id) ]
        [ details []
            [ summary [] [ text title ] ]
        ]


view : Model -> Html Msg
view { feeds } =
    div [] (List.map feedView feeds)


subscriptions : model -> Sub Msg
subscriptions model =
    Sub.batch
        [ receiveInitFeeds InitFeeds
        , receiveEntries NewEntries
        ]
