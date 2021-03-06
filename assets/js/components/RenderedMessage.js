import React, {Component} from 'react';
import {Comment, Label, Input, Popup, Button} from 'semantic-ui-react'
import EmojiConvertor from 'emoji-js';
import Linkify from 'react-linkify'
import TimeAgo from 'react-timeago'
import moment from 'moment'
import RenderedUrl from './RenderedUrl';

export default class RenderedMessage extends Component {
  constructor(props) {
    super(props);
    this.maybeRenderUrl = this.maybeRenderUrl.bind(this);
    this.maybeRenderAvatar = this.maybeRenderAvatar.bind(this);
    this.emoji = new EmojiConvertor();
  }

  maybeRenderUrl() {
    if (this.props.urlData && this.props.urlData.show) {
      return <RenderedUrl urlData={this.props.urlData} key={1} scrollDown={this.props.scrollDown}/>
    }
  }

  maybeRenderAvatar() {
    if (this.props.user && this.props.user.avatar) {
      return this.props.user.avatar
    }

    return null;
  }

  render() {
    let labels = this.props.tags.map((t, i) => {
      return (
        <Popup basic flowing key={i} trigger={<Label size="medium" as='a' onClick={this.props.onTagClick}>{t}</Label>} hoverable size='mini' content={<Button inverted icon='remove' compact size='mini' color='red' onClick={() => { this.props.removeMessageTag(this.props.id, t) }}/>}/>
      )
    });
    labels[labels.length] = <Label key={labels.length + 1} size='mini'><Input className='newTagInput' onKeyPress={(e) => this.props.handleNewTagOnMessage(e, this.props.id)} transparent placeholder='+'/></Label>

    const emojiText = this.emoji.replace_colons(this.props.text);
    const comment = (
      <Comment key={0}>
        <Comment.Avatar style={{ backgroundColor: this.props.color, height: '3.0em', width: '3.0em'}} src={this.maybeRenderAvatar()}/>
          <Comment.Content>
            <Comment.Author as='a' style={{fontSize: '16px'}}>{this.props.name}</Comment.Author>
            <Comment.Metadata style={{fontSize: '12px'}}>
              {labels}
              <TimeAgo date={moment.utc(this.props.timestamp)} minPeriod={15}/>
            </Comment.Metadata>
          <Comment.Text style={{fontSize: '16px'}}>
            {this.maybeRenderUrl()}
            <Linkify properties={{target: '_blank', rel: "nofollow"}}>
              {emojiText}
            </Linkify>
          </Comment.Text>
        </Comment.Content>
      </Comment>
    );

    return comment;
  }
}