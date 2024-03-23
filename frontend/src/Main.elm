port module Main exposing (..)

import Browser
import Html exposing (Html, article, details, div, summary, text)


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


port receiveNewFeeds : (List String -> msg) -> Sub msg


port receiveNewEntries : (List Entry -> msg) -> Sub msg


type alias Entry =
    { id : Int
    , feedid : Int
    , title : String
    , date : String
    , url : String
    }


type Msg
    = NewRawFeeds (List String)
    | NewRawEntries (List Entry)


type alias Feed =
    { title : String
    }


type alias Model =
    { feeds : List Feed
    }


init : flags -> ( Model, Cmd msg )
init _ =
    ( Model [ Feed "foo", Feed "bar" ], Cmd.none )


update : Msg -> Model -> ( Model, Cmd msg )
update msg model =
    case msg of
        NewRawFeeds feeds ->
            ( Model <| List.map Feed feeds, Cmd.none )

        NewRawEntries _ ->
            ( model, Cmd.none )


feedView : Feed -> Html msg
feedView { title } =
    article []
        [ details []
            [ summary [] [ text title ] ]
        ]


view : Model -> Html msg
view { feeds } =
    div [] (List.map feedView feeds)


subscriptions : model -> Sub Msg
subscriptions model =
    Sub.batch
        [ receiveNewFeeds NewRawFeeds
        , receiveNewEntries NewRawEntries
        ]
