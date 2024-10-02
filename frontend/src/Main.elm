port module Main exposing (..)

import Browser
import Filesize
import Html exposing (Html, a, article, button, details, div, footer, form, h1, header, img, input, main_, span, summary, text, time)
import Html.Attributes exposing (attribute, autocomplete, autofocus, class, disabled, href, id, maxlength, minlength, name, placeholder, size, src, style, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit, stopPropagationOn)
import Json.Decode as JD
import List.Extra
import Loaders
import Markdown
import OrderedDict exposing (OrderedDict)
import Set
import String exposing (fromInt)
import Task
import Time exposing (millisToPosix)
import Time.Distance exposing (inWords)


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
    , entries : OrderedDict Int (List Entry)
    , search : String
    , dbStats : Maybe DbStats
    , currentSearch : Maybe String
    , nResults : Int
    , state : State
    , now : Time.Posix
    }


type alias DbStats =
    { nPodcasts : Int
    , nEntries : Int
    , dbSize : Int
    }


type alias Feed =
    { id : Int
    , title : String
    , details : Maybe FeedDetails
    , isSelected : Bool
    , isVisible : Bool
    , nEntries : Int
    , nResults : Int
    }


type alias FeedDetails =
    { id : Int
    , home : String
    , description : String
    , language : String
    , image : String
    , author : String
    , url : String
    }


type alias Entry =
    { id : Int
    , feedid : Int
    , title : String
    , date : Int
    , url : String
    , content : EntryContent
    , isShowingDetails : Bool
    }


type EntryContent
    = EntryBlank
    | EntryWaiting
    | EntryReceived String


type State
    = Starting
    | Idle
    | WaitingForResults
    | ShowingResults
    | Error


type Msg
    = InitFeeds (List InitFeed)
    | InitClock Time.Posix
    | AskForEntries Int
    | NewEntries (List NewEntry)
    | NewInput String
    | AskForDetails Int Int
    | NewDetails EntryDetails
    | AskForSearch
    | NewSearchResults (List NewEntry)
    | NewDbStats DbStats
    | NewError String
    | NewFeedDetails FeedDetails


type alias InitFeed =
    { id : Int
    , title : String
    , nEntries : Int
    }


type alias EntryDetails =
    { id : Int
    , feedid : Int
    , content : String
    }


type alias NewEntry =
    { id : Int
    , feedid : Int
    , title : String
    , date : Int
    , url : String
    }


type alias QuestionEntryDetails =
    { entryId : Int
    , search : String
    }


port askForFeedDetails : Int -> Cmd msg


port askForEntryDetails : QuestionEntryDetails -> Cmd msg


port askForEntries : Int -> Cmd msg


port askForSearch : String -> Cmd msg


port receiveFeedDetails : (FeedDetails -> msg) -> Sub msg


port receiveDbStats : (DbStats -> msg) -> Sub msg


port receiveSearchResults : (List NewEntry -> msg) -> Sub msg


port receiveEntries : (List NewEntry -> msg) -> Sub msg


port receiveEntryDetails : (EntryDetails -> msg) -> Sub msg


port receiveInitFeeds : (List InitFeed -> msg) -> Sub msg


port receiveError : (String -> msg) -> Sub msg


init : flags -> ( Model, Cmd Msg )
init _ =
    ( Model [] OrderedDict.empty "" Nothing Nothing 0 Starting (millisToPosix 0)
    , Task.perform InitClock Time.now
    )


toEntry : NewEntry -> Entry
toEntry { id, feedid, title, date, url } =
    { id = id
    , feedid = feedid
    , title = title
    , date = date
    , url = url
    , content = EntryBlank
    , isShowingDetails = False
    }


toFeed : InitFeed -> Feed
toFeed { id, title, nEntries } =
    { id = id, title = title, details = Nothing, isSelected = False, isVisible = True, nEntries = nEntries, nResults = 0 }


toggleEntryDetails : Int -> List Entry -> List Entry
toggleEntryDetails entryId =
    List.map
        (\entry ->
            if entry.id == entryId then
                { entry
                    | isShowingDetails = not entry.isShowingDetails
                    , content =
                        if entry.isShowingDetails then
                            EntryBlank

                        else
                            EntryWaiting
                }

            else
                entry
        )


fillDetails : EntryDetails -> List Entry -> List Entry
fillDetails eDetails =
    List.map
        (\entry ->
            if entry.id == eDetails.id then
                { entry
                    | content =
                        if eDetails.content == "" then
                            EntryReceived "No description."

                        else
                            EntryReceived eDetails.content
                }

            else
                entry
        )


update : Msg -> Model -> ( Model, Cmd msg )
update msg ({ feeds, entries, search, state } as model) =
    case msg of
        NewDbStats { nEntries, nPodcasts, dbSize } ->
            ( { model | dbStats = Just <| DbStats nPodcasts nEntries dbSize }, Cmd.none )

        InitFeeds iFeeds ->
            ( { model
                | feeds = List.map toFeed iFeeds
                , state = Idle
              }
            , Cmd.none
            )

        InitClock n ->
            ( { model | now = n }, Cmd.none )

        NewInput newSearch ->
            if String.isEmpty (String.trim newSearch) then
                ( { model
                    | feeds = List.map (\feed -> { feed | isVisible = True, isSelected = False }) feeds
                    , entries = OrderedDict.empty
                    , state = Idle
                    , currentSearch = Nothing
                    , search = ""
                  }
                , Cmd.none
                )

            else
                ( { model | search = newSearch }, Cmd.none )

        AskForSearch ->
            if String.isEmpty (String.trim search) then
                ( model, Cmd.none )

            else
                ( { model
                    | state = WaitingForResults
                    , currentSearch = Just search
                  }
                , askForSearch search
                )

        NewSearchResults es ->
            ( newSearchResults model es, Cmd.none )

        AskForEntries feedId ->
            case state of
                Idle ->
                    ( toggleSelectedFeed model feedId, Cmd.batch [ askForFeedDetails feedId, askForEntries feedId ] )

                _ ->
                    ( toggleSelectedFeed model feedId, Cmd.none )

        -- TODO: getting feedid from newEntries[0] is kind of hacky
        NewEntries es ->
            ( case es of
                [] ->
                    model

                entry :: _ ->
                    { model | entries = OrderedDict.insert entry.feedid (List.map toEntry es) entries }
            , Cmd.none
            )

        -- TODO: check if already has details
        AskForDetails feedId entryId ->
            ( { model | entries = OrderedDict.update feedId (Maybe.map (toggleEntryDetails entryId)) entries }
            , askForEntryDetails
                (QuestionEntryDetails entryId <|
                    Maybe.withDefault "" model.currentSearch
                )
            )

        NewDetails ({ feedid } as entryDetails) ->
            ( { model | entries = OrderedDict.update feedid (Maybe.map (fillDetails entryDetails)) entries }
            , Cmd.none
            )

        NewError _ ->
            ( { model | state = Error }, Cmd.none )

        NewFeedDetails ({ id } as feedDetails) ->
            ( { model
                | feeds =
                    List.map
                        (\feed ->
                            if feed.id == id && feed.details == Nothing then
                                { feed | details = Just feedDetails }

                            else
                                feed
                        )
                        feeds
              }
            , Cmd.none
            )


newSearchResults : Model -> List NewEntry -> Model
newSearchResults model newEntries =
    let
        feedIds =
            List.foldl (\e -> Set.insert e.feedid) Set.empty newEntries

        feedsCounts =
            List.foldl (\e -> OrderedDict.update e.feedid (Maybe.withDefault 0 >> (+) 1 >> Just))
                OrderedDict.empty
                newEntries

        feeds =
            List.map
                (\feed ->
                    let
                        isMember =
                            Set.member feed.id feedIds
                    in
                    { feed
                        | isSelected = isMember
                        , isVisible = isMember
                        , nResults = Maybe.withDefault 0 <| OrderedDict.get feed.id feedsCounts
                    }
                )
                model.feeds

        entries =
            List.map toEntry newEntries
                |> List.foldl
                    (\entry ->
                        OrderedDict.update entry.feedid
                            (\feedEntries ->
                                case feedEntries of
                                    Nothing ->
                                        Just [ entry ]

                                    Just oldFeedEntries ->
                                        Just (entry :: oldFeedEntries)
                            )
                    )
                    OrderedDict.empty
                |> OrderedDict.map (\_ es -> List.reverse es)
    in
    { model | feeds = feeds, entries = entries, state = ShowingResults }


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
            OrderedDict.update feedid
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


open : Bool -> Html.Attribute msg
open flag =
    if flag then
        attribute "open" ""

    else
        class ""


viewFeed : Feed -> State -> Time.Posix -> OrderedDict Int (List Entry) -> Html Msg
viewFeed ({ title, id, isSelected } as feed) state now entries =
    let
        count =
            case state of
                ShowingResults ->
                    feed.nResults

                _ ->
                    feed.nEntries

        content =
            case state of
                Idle ->
                    viewFeedDetails feed :: viewFeedEntries id now entries

                _ ->
                    viewFeedEntries id now entries
    in
    article [ onClick (AskForEntries id) ]
        [ details [ open isSelected ] <|
            summary []
                [ span [] [ text title ]
                , span [] [ text (" [" ++ fromInt count ++ "]") ]
                ]
                :: content
        ]


viewFeedDetails : Feed -> Html Msg
viewFeedDetails { details, isSelected } =
    div
        [ class "episode"
        ]
        [ div [ class "feed-details" ] <|
            case details of
                Nothing ->
                    if isSelected then
                        [ Loaders.ballTriangle 60 "#fff" ]

                    else
                        [ text "..." ]

                Just feedDetails ->
                    [ img [ src feedDetails.image ] []
                    , div [ class "feed-bio" ]
                        [ div [] []
                        , Markdown.toHtml [] feedDetails.description
                        , div [ class "feed-links" ]
                            [ a [ href feedDetails.home ] [ text "Home" ]
                            , a [ href feedDetails.url ] [ text "RSS" ]
                            ]
                        ]
                    ]
        ]


viewFeedEntries : Int -> Time.Posix -> OrderedDict Int (List Entry) -> List (Html Msg)
viewFeedEntries feedId now entries =
    List.map (viewEntry feedId now) <|
        Maybe.withDefault [] (OrderedDict.get feedId entries)


onClickWithStopPropagation : msg -> Html.Attribute msg
onClickWithStopPropagation msg =
    stopPropagationOn "click" (JD.map (\m -> ( m, True )) (JD.succeed msg))


viewEntry : Int -> Time.Posix -> Entry -> Html Msg
viewEntry feedId now entry =
    div
        [ class "episode"

        -- TODO: do not ask when closing...
        , onClickWithStopPropagation (AskForDetails feedId entry.id)
        ]
        [ div [ class "episode-title" ]
            [ text entry.title ]
        , div [ class "episode-date" ]
            [ time [] [ text <| inWords (millisToPosix entry.date) now ]
            , a [ href entry.url ] [ text "Download" ]
            ]
        , div [ class "episode-content" ]
            [ if entry.isShowingDetails then
                case entry.content of
                    EntryBlank ->
                        text ""

                    EntryReceived c ->
                        Markdown.toHtml [] c

                    EntryWaiting ->
                        Loaders.ballTriangle 60 "#fff"

              else
                div [] []
            ]
        ]


viewHeader : Model -> Html Msg
viewHeader { search, state } =
    let
        isDisabled =
            state == Starting
    in
    header []
        [ h1 []
            [ text "news"
            , span [ class "pod" ] [ text "pod" ]
            ]
        , form [ onSubmit AskForSearch ]
            [ input
                [ type_ "search"
                , disabled isDisabled
                , placeholder
                    (if isDisabled then
                        ""

                     else
                        "search..."
                    )
                , id "newsearch"
                , name "newsearch"
                , value search
                , onInput NewInput
                , minlength 3
                , maxlength 30
                , size 12
                , autofocus True
                , autocomplete True
                ]
                []
            , button [ type_ "submit", style "display" "none" ] []
            ]
        ]


viewFooter : Html Msg
viewFooter =
    footer []
        [ a [ href "https://github.com/azimut/newspod" ]
            [ text "source code" ]
        ]


viewStats : Model -> Html Msg
viewStats { dbStats } =
    case dbStats of
        Nothing ->
            text ""

        Just { nPodcasts, nEntries, dbSize } ->
            div [ class "some-results" ]
                [ div [ class "npodcasts" ] [ text (fromInt nPodcasts ++ " podcasts,") ]
                , div [] [ text (fromInt nEntries ++ " episodes,") ]
                , div [] [ text (Filesize.format dbSize) ]
                ]


viewMain : Model -> Html Msg
viewMain ({ state, dbStats } as model) =
    main_ [] <|
        case state of
            Error ->
                [ div [ class "some-results" ] [ text "ERROR x(" ] ]

            Starting ->
                case dbStats of
                    Nothing ->
                        [ div [ class "some-results" ]
                            [ div [ style "visibility" "hidden" ] [ text "..." ] ]
                        , Loaders.ballTriangle 150 "#fff"
                        ]

                    Just _ ->
                        [ viewStats model
                        , if List.isEmpty model.feeds then
                            Loaders.ballTriangle 150 "#fff"

                          else
                            text ""
                        ]

            Idle ->
                viewStats model
                    :: List.map (\feed -> viewFeed feed state model.now model.entries) model.feeds

            WaitingForResults ->
                [ div [ class "loader-search" ]
                    [ Loaders.ballTriangle 150 "#fff" ]
                ]

            ShowingResults ->
                let
                    filteredFeeds =
                        List.filter .isVisible model.feeds
                in
                case filteredFeeds of
                    [] ->
                        [ div [ class "no-results" ] [ text "no results found :(" ] ]

                    _ ->
                        let
                            nResults =
                                List.foldl (\f acc -> f.nResults + acc) 0 filteredFeeds

                            message =
                                case nResults of
                                    1 ->
                                        fromInt nResults ++ " result found"

                                    _ ->
                                        fromInt nResults ++ " results found"

                            feedIds =
                                OrderedDict.keys model.entries |> List.reverse
                        in
                        div [ class "some-results" ] [ text message ]
                            :: List.map
                                (\feed -> viewFeed feed state model.now model.entries)
                                (sortFeeds model.feeds feedIds [])


view : Model -> Html Msg
view model =
    case model.state of
        Error ->
            div []
                [ viewHeader model
                , viewMain model
                ]

        Starting ->
            div []
                [ viewHeader model
                , viewMain model
                ]

        Idle ->
            div []
                [ viewHeader model
                , viewMain model
                , viewFooter
                ]

        WaitingForResults ->
            div []
                [ viewHeader model
                , viewMain model
                ]

        ShowingResults ->
            div []
                [ viewHeader model
                , viewMain model
                , viewFooter
                ]


sortFeeds : List Feed -> List Int -> List Feed -> List Feed
sortFeeds feeds ids acc =
    case ids of
        [] ->
            acc

        id :: rest ->
            case List.Extra.find (\feed -> feed.id == id) feeds of
                Nothing ->
                    sortFeeds feeds rest acc

                Just foundFeed ->
                    sortFeeds feeds rest (foundFeed :: acc)


subscriptions : model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ receiveInitFeeds InitFeeds
        , receiveEntries NewEntries
        , receiveEntryDetails NewDetails
        , receiveSearchResults NewSearchResults
        , receiveDbStats NewDbStats
        , receiveError NewError
        , receiveFeedDetails NewFeedDetails
        ]
