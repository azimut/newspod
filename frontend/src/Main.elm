port module Main exposing (..)

import Browser
import Dict exposing (Dict)
import Html exposing (Html, a, article, details, div, footer, header, input, main_, span, summary, text, time)
import Html.Attributes exposing (class, href, placeholder, value)
import Html.Events exposing (onClick, onInput, stopPropagationOn)
import Json.Decode as JD
import Loaders
import Markdown
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
    , isShowingDetails : Bool
    }


type Msg
    = InitFeeds (List InitFeed)
    | AskForEntries Int
    | NewEntries (List NewEntry)
    | NewInput String
    | AskForDetails Int Int
    | NewDetails EntryDetails


type alias InitFeed =
    { id : Int
    , title : String
    , nEntries : Int
    }


type alias EntryDetails =
    { id : Int
    , feedid : Int
    , description : String
    , content : String
    }


type alias NewEntry =
    { id : Int
    , feedid : Int
    , title : String
    , date : String
    , url : String
    }


port askForEntryDetails : Int -> Cmd msg


port askForEntries : Int -> Cmd msg


port receiveEntries : (List NewEntry -> msg) -> Sub msg


port receiveEntryDetails : (EntryDetails -> msg) -> Sub msg


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
    , isShowingDetails = False
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


toggleEntryDetails : Int -> List Entry -> List Entry
toggleEntryDetails id entries =
    List.map
        (\entry ->
            if entry.id == id then
                { entry | isShowingDetails = not entry.isShowingDetails }

            else
                entry
        )
        entries


fillDetails : EntryDetails -> List Entry -> List Entry
fillDetails eDetails entries =
    List.map
        (\entry ->
            if entry.id == eDetails.id then
                { entry | content = eDetails.content, description = eDetails.description }

            else
                entry
        )
        entries


closeDetailsIfOpen : Entry -> Entry
closeDetailsIfOpen entry =
    if entry.isShowingDetails then
        { entry | isShowingDetails = False }

    else
        entry


update : Msg -> Model -> ( Model, Cmd msg )
update msg ({ entries } as model) =
    case msg of
        AskForDetails feedId entryId ->
            -- TODO: check if already has details
            ( { model | entries = Dict.update feedId (Maybe.map (toggleEntryDetails entryId)) entries }
            , askForEntryDetails entryId
            )

        NewDetails ({ feedid } as entryDetails) ->
            ( { model | entries = Dict.update feedid (Maybe.map (fillDetails entryDetails)) entries }
            , Cmd.none
            )

        NewInput newSearch ->
            ( { model | search = newSearch }, Cmd.none )

        AskForEntries feedId ->
            if Dict.member feedId entries then
                ( toggleSelectedFeed model feedId, Cmd.none )

            else
                ( toggleSelectedFeed model feedId, askForEntries feedId )

        InitFeeds iFeeds ->
            ( Model (List.map initFeed iFeeds) Dict.empty ""
            , Cmd.none
            )

        NewEntries es ->
            ( newEntries model es, Cmd.none )


toggleSelectedFeed : Model -> Int -> Model
toggleSelectedFeed ({ feeds, entries } as model) feedid =
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
        , entries =
            Dict.update feedid
                (Maybe.map
                    (List.map
                        (\entry ->
                            if entry.isShowingDetails then
                                { entry | isShowingDetails = False }

                            else
                                entry
                        )
                    )
                )
                entries
    }


viewFeed : Feed -> Dict Int (List Entry) -> Html Msg
viewFeed { title, id, nEntries, isSelected } entries =
    article [ onClick (AskForEntries id) ]
        [ details [] <|
            summary
                [ if isSelected then
                    class "selected"

                  else
                    class ""
                ]
                [ text (title ++ " [" ++ fromInt nEntries ++ "]") ]
                :: viewFeedEntries id entries
        ]


viewFeedEntries : Int -> Dict Int (List Entry) -> List (Html Msg)
viewFeedEntries feedId entries =
    List.map (viewEntry feedId) <|
        Maybe.withDefault [] (Dict.get feedId entries)


onClickWithStopPropagation : msg -> Html.Attribute msg
onClickWithStopPropagation msg =
    stopPropagationOn "click" (JD.map (\m -> ( m, True )) (JD.succeed msg))


viewEntry : Int -> Entry -> Html Msg
viewEntry feedId { title, date, url, id, isShowingDetails, content } =
    div
        [ class "episode"

        -- TODO: do not ask when closing...
        , onClickWithStopPropagation (AskForDetails feedId id)
        ]
        [ div [ class "episode-title" ]
            [ text title ]
        , div [ class "episode-date" ]
            [ a [ href url ]
                [ time [] [ text date ] ]
            ]
        , if isShowingDetails then
            Markdown.toHtml [] content

          else
            div [] []
        ]


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

                    -- , input [ placeholder "search", value search, onInput NewInput ] []
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
        , receiveEntryDetails NewDetails
        ]
